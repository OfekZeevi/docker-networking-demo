# Docker Networking Demo

This repo was created to demonstrate the basic usage of docker, and more specifically how docker networking works.
This should be used for educational purposes only.

Written by Ofek Zeevi.

## Installation Guide
To install docker on your system, run
```bash
sudo <package-manager> install docker.io
```
with the appropriate package manager for your system (e.g. `apt` for ubuntu, `yum` for rhel etc.)
Once installed, make sure it's running by using 
```bash
sudo systemctl enable --now docker
```
This will both start docker's systemd service and make sure it starts automatically after a reboot.
You can check that it's running at all times by using `sudo systemctl status docker`.

To allow your own user to perform actions with docker (like starting and stopping containers), be sure to run
```bash
sudo usermod -aG docker <your-user>
```
and then restart docker with `sudo systemctl restart docker`, and log out and back in. Check that you have permissions
by running `docker ps`. If you encounter problems at this point, try restarting your computer / VM.

Finally, to use docker-compose, run
```bash
sudo <package-manager> install docker-compose
```
If the package isn't available, try `pip install docker-compose` instead. Finally, make sure it's installed by running
`docker-compose -v`.

**Note:** If you intend on running the `.sh` scripts in this repo, make sure to run
```bash
sudo chmod +x *.sh */*.sh
```

## Demo #0 - basic docker usage
To run a basic docker image, use
```bash
docker run -it alpine sh
```
Play around with it to see that you're in a separate namespace - different file system (`ls /`), different PIDs 
(`ps -fe`), different network (`ip a`) and so on. To exit, use `ctrl+d`.

Next, let's play around with the file system. Run 
```bash
docker run -it -v /tmp:/host-tmp alpine sh
```
to create a shared directory between the host and the container - the host's `/tmp` will be accessible from within the 
container through the `/host-tmp` directory. You can create files in one and then read them in the other.

For the next demo, we're gonna run a container in the background. We can use `-d` for that.
For example, run
```bash
docker run -d alpine sleep 99999
```
and then `docker ps` to see that your container is running. We can even see the `sleep` command by using 
`sudo ps -fe | grep sleep` in our main shell. But that's not very exciting, it's literally doing nothing, so try
```bash
docker run -d alpine watch date
```
Now our container prints the date and time every 2 seconds! Use `docker logs <container-name>` to see that.

Finally, we're gonna run a container that actually does something - in this case, an HTTP server. See the contents of
`server/Dockerfile` to see how we describe what should be installed in our docker image, which files it should have and 
what commands it should run on startup. Enter the `server` dir and run 
```bash
docker build -t demo-server .
``` 
or simply `./build.sh`. This will create an image named "demo-server" with our configuration. Run it with 
```bash
docker run -d --name server-1 demo-server
```
You can see it with `docker ps`, but unfortunately it doesn't work! `wget -q -O - http://localhost/` and we get no response.
But run `docker exec -it server-1 sh` and then `wget` again and suddenly it does! The reason is that it's listening on
port 80 in a separate namespace. To connect the main network namespace with the internal one, run
```bash
docker run -d -p 4000:80 --name server-1 demo-server
```
or `./run.sh`, and now do `wget` for port 4000.

## Demo #1 - basic network separation with namespaces
We can create a dummy interface and move it to a separate namespace pretty easily:
```bash
ip link add dev my-if type dummy  # Create the interface "my-if"
ip link set my-if up              #
ip addr add dev my-if 1.2.3.4/32  # Give it ip address 1.2.3.4
ping 1.2.3.4                      # Ping works

ip netns add my-net                                    # Create the network namespace "my-net"
ip link set dev my-if netns my-net                     # Move "my-if" into "my-net"
ip netns exec my-net ip link set lo up                 # 
ip netns exec my-net ip link set my-if up              # 
ip netns exec my-net ip addr add dev my-if 1.2.3.4/32  # Give it ip address 1.2.3.4 again
ping 1.2.3.4                                           # Doesn't respond to ping!
ip netns exec my-net ping 1.2.3.4                      # Ping works only from within namespace...
ip netns exec my-net ping 8.8.8.8                      # But ping to the outside world doesn't work
```
But unfortunately, in this way we cannot communicate from the main network namespace to the internal one.
What we need is **veth** - a special kind of interface that is created in connected pairs, so that we can move one side
into the network namespace, but keep the other side in the main namespace, and so communication works between them.
```bash
sudo ip link add dev veth0 type veth peer name veth1
sudo ip link set veth1 netns my-net

sudo ip link set veth0 up
sudo ip addr add dev veth0 10.11.12.13/24

sudo ip netns exec my-net ip link set veth1 up
sudo ip netns exec my-net ip addr add dev veth1 10.11.12.14/24

ping 10.11.12.14
sudo ip netns exec my-net ping 10.11.12.13
```
Now we know how to separate interfaces into different namespaces but still allow them to communicate!

Finally, we can show that this is indeed what docker does. Run
```bash
docker run -d --name test alpine sleep 99999
ip a                                          # Shows one end of the veth
docker exec test ip a                         # Shows the other end of the veth
ping 172.17.0.2                               # Ping works from the host!
```

## Demo #2 - how containers communicate with the outside world
We can run a container and it'll magically allow us to communicate with the outside world. For example,
```bash
cd server && ./run.sh
docker exec server-1 ping 8.8.8.8
```
How?
The answer has three parts: a bridge, iptables and ipv4 forwarding.
First of all, let's show the bridge that makes the magic happens. Running our server again, we use
```bash
sudo brctl show
```
to see that docker created a bridge and placed one veth-end into it. A bridge is like a virtual switch. However,
it also creates a local virtual interface for easier usage, in this case that's "docker0" (`ip a show docker0`).
So for the first stage, linux create a bridge and gave its virtual interface the address 172.17.0.1. It then created
the veth-pair, placed one end in the container's NS (and gave it an IP address) and the other in the bridge. Finally,
it configured the container to reach out for "docker0" as its default gateway.
```bash
sudo lsns -t net
sudo nsenter --net=<docker-network-ns-path> ip route
```
Next up, we need to setup a NAT - for that we can use iptables.
```bash
iptables -nvL -t nat | grep docker0
```

Finally, we also need to allow linux to pass packets between interfaces. The condition is: whenever a packet reaches
an interface, with the dst mac pointing to the interface but the ip address is different, then forward it to the best
match you have in your forwarding table. This is governed by `sysctl net.ipv4.conf.all.forwarding`. If we run
```bash
sudo sysctl -w net.ipv4.conf.all.forwarding=0
```
the communication from the container to the outside world will stop working! Run `docker exec server-1 ping 8.8.8.8` to
see. You can enable it back (with `=1`) to make it work again. All three parts are required so that the packet:
1. Reaches the default gateway, which is an interface in the global network namespace,
2. Is forwarded to the best matching interface based on linux's routing table, and
3. Is transferred using NAT to the outside world (so that we'll be able to receive the answers).

## Demo #3 - how containers communicate with each other
For starters, run
```bash
./run-network-demo.sh
```
to set up everything. Interestingly, we can address the server from the client both using IP or using its name! How?
```bash
docker exec server-1 ip a    # find the 172.17.*.* address of the server
docker exec -it client-1 sh  # enter the client container
ping <server-1-ip-address>   # this should work
ping server-1                # but somehow this also works
```

IP communication is easier. By using `brctl show` again, we can clearly see that there's a bridge with two veth 
interfaces in it - that is our docker network! (we created a custom one, and that's why it's not called docker0).
So the packets enter from within the container namespace to the veth, pop out the other end into the bridge, are
then switched to the other container's veth-pair, and pop out inside the other container's namespace.

As for DNS names - something cleverer is happening here...
```bash
docker inspect server-1                                # has a DNS name configured here
docker exec client-1 cat /etc/resolv.conf              # look at the container's DNS server configuration
sudo lsns -t net                                       # look for the client network NS
sudo nsenter --net=<path-to-client-ns> netstat -tupln  # dockerd is listening!
```
So apparently whenever we use a custom network, for every container - dockerd creates a socket **inside** that network
NS, and so it receives all the DNS requests from all the containers. It then uses the configuration seen on `inspect`
to find the correct container and its IP address.

You can run `./stop-network-demo.sh` and then
```bash
docker-compose up -d
```
and look at `brctl show` (or `docker network ls`) to see that docker-compose does this automatically! It creates
and network and puts both containers inside that network for DNS to work.

## Demo #4 - how the outside world can communicate with the container
Interestingly, docker's solution is quite simple here. After running the full setup, run
```bash
sudo netstat -tupln | grep 4000
```
you'll see that there's a process called `docker-proxy` listening on that port. We can easily see it with
```bash
sudo ps -fe | grep docker-proxy
```
It has run-params with the specific IP addresses and ports it should bind and forward to, and it just performs the
proxy for us. This is simple because it makes sure the host knows that this port is available and works accross many
different systems.
And for each exposed port, docker will just spin up another instance of that process!

## Summary
There are many interesting things about docker networking, but as this demo hopefully shows, they all rely on 
fundamental mechanisms of linux  networking, and they are all tracable and understandable if you dive deep enough.
Enjoy!


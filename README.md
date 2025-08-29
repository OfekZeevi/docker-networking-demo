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

## Demo #1 - basic docker usage
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

## Demo #2 - basic network separation with namespaces
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
We can run a container and it'll magically allow us to communicate with the outside world. How?

## On general computer
ip a
ip route
(you can del and add route with different ip addr to show how it works)
(or del it and show that it breaks the container network)
sudo tcpdump -ni eth0
sudo tcpdump -ni docker0
sudo ps -fe | grep docker-proxy
sudo netstat -tupln | grep 4000

brctl show (all container network interfaces have one part of their veth in there)

## Docker commands
docker network ls
docker run --network <net-name> ...
(then names will be automatically resolved between containers on the same network)
docker inspect <container_name> (show the network section, specifically DNS names)

docker-compose up -d (show the network and everything)

## Namespace commands
sudo lsns -t net | grep python
sudo nsenter --net=<path e.g. /run/docker/netns/d730f0...> ip a

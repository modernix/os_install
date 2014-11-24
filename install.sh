#!/bin/bash

# elevate our status in the world
#sudo -i
HOST_NAME="os.local"

hostname $HOST_NAME
sed -i "s/stackinabox/$HOST_NAME/g" /etc/hostname
echo -e "$( hostname -I | awk '{ print $2 }' )\t$HOST_NAME" >> /etc/hosts

# SNAT the VirtualBox "management" network so OpenStack's VMs can route to Internet on host.
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# SNAT the '192.168.27.x' network so OpenStack managed VMs can route to any other ip running in the same subnet
iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE

# Needed to allow OpenStack managed VM's to recieve dhcp assignments from Neutron vDHCP servers
iptables -A POSTROUTING -t mangle -p udp --dport bootpc -j CHECKSUM --checksum-fill

# clone devstack repo localy
echo "Cloning DevStack repo"
cd /opt
git clone https://github.com/openstack-dev/devstack.git

# optionally check out just the "tag" you want
echo "Checkout 'stable/icehouse' branch of DevStack"
cd devstack
git checkout stable/icehouse

# add local.conf to /opt/devstack folder
cp /opt/os_install/local.conf /opt/devstack/

# create stack user using devstack's provided script
/opt/devstack/tools/create-stack-user.sh

# make stack user owner of /opt/devstack
chown -R stack:stack /opt/devstack

# set ip address for eth2 to 0.0.0.0
ifconfig eth2 0.0.0.0

# turn on promiscuous mode on eth2 (172.24.4.x)
ifconfig eth2 promisc

# enable eth2 
ip link set dev eth2 up

# gentelmen start your engines
echo "Installing DevStack"
sudo -u stack -H ./stack.sh

# add eth2 as a port on the bridge
ovs-vsctl add-port br-ex eth2

# assign ip to br-ex
ifconfig br-ex 172.24.4.2

# need to setup openstack auth info for following commands
source /opt/devstack/openrc

# add DNS nameserver entries to "private" subnet in 'demo' tenant
echo "Updating dns_nameservers on the 'demo' tenant's private subnet"
neutron subnet-update private-subnet --dns_nameservers list=true 8.8.4.4 8.8.8.8

# Heat needs to launch instances with a keypair, so we need to generate one
#echo "Generating a new keypair for the 'demo' tenant"
#echo "private key 'demo_key.priv' will be copied to shared /vagrant folder for ease of use."
#nova keypair-add demo_key > demo_key.priv
#mv demo_key.priv /vagrant/
#chmod 600 /vagrant/demo_key.priv

# need to be an administrator for the following nova commands
source /opt/devstack/openrc admin admin

# Create an 'internal' network for the 'admin' tenant and add router to external 'public' network
#tenant=$(keystone tenant-list | awk '/admin/ {print $2}')
#neutron net-create internal
#neutron subnet-create --name internal-subnet --gateway 10.0.10.1 internal 10.0.10.0/24
#neutron router-create router2 
#neutron router-interface-add router2 internal-subnet 
#neutron router-gateway-set router2 public 

# add DNS nameserver entries to "internal" subnet in 'admin' tenant
#echo "Updating dns_nameservers on the 'admin' tenant's private subnet"
#neutron subnet-update internal-subnet --dns_nameservers list=true 8.8.8.8 8.8.4.4 10.0.2.3 10.0.10.1

# Heat needs to launch instances with a keypair, so we need to generate one
#echo "Generating a new keypair for the 'admin' tenant"
#echo "private key 'admin_key.priv' will be copied to shared /vagrant folder for ease of use."
#nova keypair-add admin_key > admin_key.priv
#mv admin_key.priv /vagrant/
#chmod 600 /vagrant/admin_key.priv

# Add HEAT Compatible Images to OpenStack
echo "Adding HEAT compatible image 'Ubuntu-14.04.x86_64' to OpenStack"
mkdir -p /opt/os/images
cd /opt/os/images
wget --no-verbose -N http://cloud.fedoraproject.org/fedora-20.x86_64.qcow2
glance image-create --name="Fedora20-x86_64" --disk-format=qcow2 --container-format=bare --is-public=True < fedora-20.x86_64.qcow2

wget --no-verbose -N http://uec-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64-disk1.img
glance image-create --name="Ubuntu-14.04.x86_64" --disk-format=qcow2 --container-format=bare --is-public=True < trusty-server-cloudimg-amd64-disk1.img

# remove non-working flavors
nova flavor-delete m1.tiny
nova flavor-delete m1.small
nova flavor-delete m1.medium
nova flavor-delete m1.large
nova flavor-delete m1.xlarge

# Add new Flavor that can run above images
echo "Creating new flavors that can be used on this vm"
nova flavor-create m1.small auto 512 10 1
nova flavor-create m1.medium auto 1024 10 1
nova flavor-create m1.large auto 1536 10 2
nova flavor-create m1.xlarge auto 2048 10 2

# add admin role to admin user in the demo tenant
#keystone user-role-add --user admin --role admin --tenant demo

# add Member role to admin user in the admin tenant
#keystone user-role-add --user admin --role Member --tenant admin

# delete the invisible_to_admin tenant (not needed)
keystone tenant-delete invisible_to_admin

# add devstack to init.d so it will automatically start/stop with the machine
cp /opt/os /etc/init.d/devstack
chmod +x /etc/init.d/devstack
update-rc.d devstack defaults 98 02

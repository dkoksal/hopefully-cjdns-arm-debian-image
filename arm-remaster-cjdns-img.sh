#!/bin/bash

# build your own peer-addressable armel or armhf SD card image using cjdns
# officially targeting beaglebone, not yet super tested, but armel should 
# be compatible with Raspberry Pi

# build your own Raspberry Pi SD card
#
# by Klaus M Pfeiffer, http://blog.kmp.or.at/ , 2012-06-24

# 2012-06-24
#	just checking for how partitions are called on the system (thanks to Ricky Birtles and Luke Wilkinson)
#	using http.debian.net as debian mirror, see http://rgeissert.blogspot.co.at/2012/06/introducing-httpdebiannet-debians.html
#	tested successfully in debian squeeze and wheezy VirtualBox
#	added hint for lvm2
#	added debconf-set-selections for kezboard
#	corrected bug in writing to etc/modules
# 2012-06-16
#	improoved handling of local debian mirror
#	added hint for dosfstools (thanks to Mike)
#	added vchiq & snd_bcm2835 to /etc/modules (thanks to Tony Jones)
#	take the value fdisk suggests for the boot partition to start (thanks to Mike)
# 2012-06-02
#       improoved to directly generate an image file with the help of kpartx
#	added deb_local_mirror for generating images with correct sources.list
# 2012-05-27
#	workaround for https://github.com/Hexxeh/rpi-update/issues/4 just touching /boot/start.elf before running rpi-update
# 2012-05-20
#	back to wheezy, http://bugs.debian.org/672851 solved, http://packages.qa.debian.org/i/ifupdown/news/20120519T163909Z.html
# 2012-05-19
#	stage3: remove eth* from /lib/udev/rules.d/75-persistent-net-generator.rules
#	initial

# you need at least
# apt-get install binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools

deb_mirror="http://http.debian.net/debian"
#deb_local_mirror="http://debian.kmp.or.at:3142/debian"

bootsize="64M"
deb_release="wheezy"

device=$1
buildenv="/root/rpi"
rootfs="${buildenv}/rootfs"
bootfs="${rootfs}/boot"

mydate=`date +%Y%m%d`

if [ "$deb_local_mirror" == "" ]; then
  deb_local_mirror=$deb_mirror  
fi

image=""


if [ $EUID -ne 0 ]; then
  echo "this tool must be run as root"
  exit 1
fi

if ! [ -b $device ]; then
  echo "$device is not a block device"
  exit 1
fi

if [ "$device" == "" ]; then
  echo "no block device given, just creating an image"
  mkdir -p $buildenv
  image="${buildenv}/rpi_basic_${deb_release}_${mydate}.img"
  dd if=/dev/zero of=$image bs=1MB count=1000
  device=`losetup -f --show $image`
  echo "image $image created and mounted as $device"
else
  dd if=/dev/zero of=$device bs=512 count=1
fi

fdisk $device << EOF
n
p
1

+$bootsize
t
c
n
p
2


w
EOF


if [ "$image" != "" ]; then
  losetup -d $device
  device=`kpartx -va $image | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
  device="/dev/mapper/${device}"
  bootp=${device}p1
  rootp=${device}p2
else
  if ! [ -b ${device}1 ]; then
    bootp=${device}p1
    rootp=${device}p2
    if ! [ -b ${bootp} ]; then
      echo "uh, oh, something went wrong, can't find bootpartition neither as ${device}1 nor as ${device}p1, exiting."
      exit 1
    fi
  else
    bootp=${device}1
    rootp=${device}2
  fi  
fi

mkfs.vfat $bootp
mkfs.ext4 $rootp

mkdir -p $rootfs

mount $rootp $rootfs

cd $rootfs

debootstrap --foreign --arch armel $deb_release $rootfs $deb_local_mirror
cp /usr/bin/qemu-arm-static usr/bin/
LANG=C chroot $rootfs /debootstrap/debootstrap --second-stage

mount $bootp $bootfs

echo "deb $deb_local_mirror $deb_release main contrib non-free
$deb_mirror jessie main contrib non-free
" > etc/apt/sources.list

echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait" > boot/cmdline.txt

echo "proc            /proc           proc    defaults        0       0
/dev/mmcblk0p1  /boot           vfat    defaults        0       0
" > etc/fstab

echo "isapeer" > etc/hostname

echo "auto lo
iface lo inet loopback

auto eth0
    iface eth0 inet static
    #set your static IP below
    address 192.168.1.12

    #set your default gateway IP here
    gateway 192.168.1.1

    netmask 255.255.255.0
    network 192.168.1.0
    broadcast 192.168.1.255

" > etc/network/interfaces

echo "vchiq
snd_bcm2835
ipv6
" >> etc/modules

echo "console-common	console-data/keymap/policy	select	Select keymap from full list
console-common	console-data/keymap/full	select	de-latin1-nodeadkeys
" > debconf.set

echo "#!/bin/bash
debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update 
apt-get -y install git-core binutils ca-certificates
wget http://goo.gl/1BOfJ -O /usr/bin/rpi-update
chmod +x /usr/bin/rpi-update
mkdir -p /lib/modules/3.1.9+
touch /boot/start.elf
rpi-update
apt-get -y install locales console-common ntp openssh-server less nano ferm git
mkdir hypenet
cd hypenet
working=$(pwd)
scriptname='/hyperboria.sh'
workingscriptname=$working$scriptname
git clone https://gist.githubusercontent.com/clehner/4453993/raw/ef9ff88e288cb0cc0557fcd9ad3c6d7a0dd96c44/hyperboria.sh
chmod +x $workingscriptname
ln -s $workingscriptname /etc/init.d/cjdns
service cjdns install
cd /etc
rm cjdroute.conf
/opt/cjdns/cjdroute --genconf > cjdroute.pre
/opt/cjdns/cjdroute --cleanconf < cjdroute.pre > cjdroute.conf
rm cjdroute.pre
mkdir /home/WebServ/
cd /home/
debootstrap --foreign --arch armel $deb_release /home/WebServ $deb_local_mirror
chroot echo '#! /bin/sh
mount none -t proc /proc
mount none -t sysfs /sys
mount none -t devpts /dev/pts
cd home
apt-get update && apt-get dist-upgrade
service lighttpd start
' >> /mount.sh
chroot /home/WebServ/ chmod +x mount.sh
chroot /home/WebServ/ /mount.sh
chroot /home/WebServ/ apt=get install lighttpd php5-cgi
chroot echo \"deb $deb_mirror $deb_release main contrib non-free
$deb_mirror jessie main contrib non-free
\" > etc/apt/sources.list
echo '# ferm cjdns-ready firewall rules revision 1
# http://ferm.foo-projects.org
# 
table filter {
    chain INPUT {
        policy DROP;
        # connection tracking
        mod state state INVALID DROP;
        mod state state (ESTABLISHED RELATED) ACCEPT;
        # allow local packet
        interface lo ACCEPT;
        # respond to ping
        #proto icmp ACCEPT;
        # snmp - if you need for monitoring as CACTI, ICINGA, ...
        proto udp dport snmp ACCEPT;
        # allow tcp SSH, FTP, HTTP, HTTPS, ...
        # proto tcp dport (http https) ACCEPT;
	# allow cjdns connections, this peer is transient, a sort of hotspot.
	proto udp dport (23123) ACCEPT;
    }
    # outgoing connections are not limited
    chain OUTPUT {
        policy ACCEPT;
    }
    # only for a router
    chain FORWARD {
        policy DROP;
    }
}
# IPv6 rules
domain ip6 table filter {
    chain INPUT {
        policy DROP;
        # connection tracking
        mod state state INVALID DROP;
        mod state state (ESTABLISHED RELATED) ACCEPT;
        # allow local connections
        interface lo ACCEPT;
        # allow ICMP (for neighbor solicitation, like ARP for IPv4)
        #proto ipv6-icmp ALLOW;
        # allow tcp connections
        #proto tcp dport (http https) ACCEPT;
	# allow cjdns connections, this peer is transient, a sort of hotspot.
	proto udp dport (23123) ACCEPT;
        interface tun0{
            # allow tcp connections
            proto tcp dport (http https) ACCEPT;
        }
    }
    # outgoing connections are not limited
    chain OUTPUT policy ACCEPT;
    # only for a router
    chain FORWARD policy DROP;
}
# allow no more than 3 ssh attempts from a source ip in 50 minutes
domain (ip ip6) table filter chain INPUT {
  protocol tcp dport ssh @subchain {
    mod recent name SSH {
      set NOP;
      update seconds 3000 hitcount 3 @subchain {
	LOG log-prefix \"Blocked-ssh: \" log-level warning;
	DROP;
      }
    }
    ACCEPT;
  }
}
# log all other INPUT
domain (ip ip6) table filter chain INPUT {
    mod limit limit 3/min limit-burst 10 LOG log-prefix \"INPUT-rejected: \" log-level debug;
    REJECT;
}' >> /home/ferm.conf
echo '#! /bin/sh
ferm /home/ferm.conf
' >> /home/loadfw.sh
chmod +x /home/loadfw.sh
echo '
@reboot /home/loadfw.sh
@reboot sleep 30 && /etc/init.d/cjdns update
@reboot /home/WebServ/startpws.sh
#daily reboot
'>> /home/defcron
crontab -u \$whoami /home/defcron
echo \"root:isapeer\" | chpasswd
sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f third-stage
" > third-stage
chmod +x third-stage
LANG=C chroot $rootfs /third-stage
echo "deb $deb_mirror $deb_release main contrib non-free
$deb_mirror jessie main contrib non-free
" > etc/apt/sources.list
echo "#!/bin/bash
aptitude update
aptitude clean
apt-get autoremove
apt-get autoclean
apt-get clean
" > cleanup
chmod +x cleanup
LANG=C chroot $rootfs /cleanup

cd

umount $bootp
umount $rootp

if [ "$image" != "" ]; then
  kpartx -d $image
  echo "created image $image"
fi


echo "done."


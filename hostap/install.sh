#! /bin/bash
#
DEBUG=1

myname="`basename $0`"
# Required pacakges
PKGLIST="hostapd dnsmasq iptables iptables-persistent"

function dbgecho { if [ ! -z "$DEBUG" ] ; then echo "$*"; fi }

# ===== function is_pkg_installed

function is_pkg_installed() {

return $(dpkg-query -W -f='${Status}' $1 2>/dev/null | grep -c "ok installed")
}

# ===== function is_rpi3

function is_rpi3() {

CPUINFO_FILE="/proc/cpuinfo"
HAS_WIFI=0

piver="$(grep "Revision" $CPUINFO_FILE)"
piver="$(echo -e "${piver##*:}" | tr -d '[[:space:]]')"

case $piver in
a01040)
   echo " Pi 2 Model B Mfg by Unknown"
;;
a01041)
   echo " Pi 2 Model B Mfg by Sony"
;;
a21041)
   echo " Pi 2 Model B Mfg by Embest"
;;
a22042)
   echo " Pi 2 Model B with BCM2837 Mfg by Embest"
;;
a02082)
   echo " Pi 3 Model B Mfg by Sony"
   HAS_WIFI=1
;;
a22082)
   echo " Pi 3 Model B Mfg by Embest"
   HAS_WIFI=1
;;
esac

return $HAS_WIFI
}

# ===== function copy_dnsmasq
function copy_dnsmasq() {
# Create a new file

cat > /$1/dnsmasq.conf <<EOT
interface=wlan0      # Use interface wlan0
listen-address=10.0.44.1
bind-interfaces      # Bind to the interface to make sure we aren't sending things elsewhere
server=8.8.8.8       # Forward DNS requests to Google DNS
domain-needed        # Don't forward short names
bogus-priv           # Never forward addresses in the non-routed address spaces.
dhcp-range=10.0.44.201,10.0.44.239,12h
EOT
}

# ===== function copy_hostapd

function copy_hostapd() {
echo "copying to /$1/hostapd.conf"
# Create a new file

cat > /$1/hostapd.conf <<EOT
interface=wlan0

# Use the nl80211 driver with the brcmfmac driver
driver=nl80211

# This is the name of the network
ssid=WL2K

# Use the 2.4GHz band
hw_mode=g

# Use channel 7
channel=7

# Enable 802.11n
ieee80211n=1

# Enable WMM
wmm_enabled=1

# Enable 40MHz channels with 20ns guard interval
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]

# Accept all MAC addresses
macaddr_acl=0

# Require clients to know the network name
#ignore_broadcast_ssid=0

# Use WPA authentication
#auth_algs=1

# Use WPA2
#wpa=2

# Use a pre-shared key
#wpa_key_mgmt=WPA-PSK

# The network passphrase, set password Here
#wpa_passphrase=

# Use AES, instead of TKIP
##wpa_pairwise=CCMP
#rsn_pairwise=CCMP
EOT
}

# ===== function dnsmasq_config

function dnsmasq_config() {
echo "copying to /$1/dnsmasq.conf"

if [ ! -f /etc/dnsmasq.conf ] ; then
   copy_dnsmasq etc
else
   echo "/etc/dnsmasq.conf already exists."
   copy_dnsmasq tmp
   echo "=== diff of current dnsmasq config ==="
   diff -b /etc/dnsmasq.conf /tmp
   echo "=== end diff ==="
fi
}

# ===== hostapd_config

function hostapd_config() {
if [ ! -f /etc/hostapd/hostapd.conf ] ; then
   copy_hostapd "etc/hostapd"
else
   echo "/etc/hostapd/hostapd.conf already exists."
   copy_hostapd tmp
   echo "=== diff of current dnsmasq config ==="
   diff -b /etc/hostapd/hostapd.conf /tmp
   echo "=== end diff ==="
fi
}


# ===== main

echo "Install hostap on an RPi 3"

is_rpi3
if [ $? -eq "0" ] ; then
   echo "Not running on an RPi 3"
#   exit 1
fi

# check if packages are installed
dbgecho "Check packages: $PKGLIST"

for pkg_name in `echo ${PKGLIST}` ; do

   is_pkg_installed $pkg_name
   if [ $? -eq 0 ] ; then
      echo "$myname: Need to Install $pkg_name program"
      apt-get -qy install $pkg_name
   fi
done

echo "Configuring: hostapd.conf"
hostapd_config

# edit hostapd to use new config file
sed -i 's;\#DAEMON_CONF="";DAEMON_CONF="/etc/hostapd/hostapd.conf";' /etc/default/hostapd


echo "Configuring: dnsmasq"
if [ -f "/etc/dnsmasq.conf" ] ; then
   dnsmasq_linecnt=$(wc -l /etc/dnsmasq.conf)
   # get rid of everything except line count
   dnsmasq_linecnt=${dnsmasq_linecnt%% *}
   dbgecho "dnsmasq.conf line count: $dnsmasq_linecnt"
   if (("$dnsmasq_linecnt" > "10")) ; then
      mv /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
      echo "Original dnsmasq.conf saved as .backup"
   fi
fi
dnsmasq_config

# set up IPV4 forwarding
echo "Set IPV4 forwarding"
ipf=$(cat /proc/sys/net/ipv4/ip_forward)
echo "ip_forward is $ipf"
if [ $ipf = "0" ] ; then
  sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
fi

sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

echo "setup iptables"
#echo "add iptables-restore to rc.local"
# or use iptables-persistent
CREATE_IPTABLES=false
IPTABLES_FILES="/etc/iptables.ipv4.nat /lib/dhcpcd/dhcpcd-hooks/70-ipv4.nat"
for ipt_file in `echo ${IPTABLES_FILES}` ; do

   if [ -f $ipt_file ] ; then
      echo "iptables file: $ipt_file exists"
   else
      echo "Need to create iptables file: $ipt_file"
      CREATE_IPTABLES=true
   fi
done

if [ "$CREATE_IPTABLES" = "true" ] ; then
   iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
   iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
   iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
   sh -c "iptables-save > /etc/iptables.ipv4.nat"

   iptables -t nat -S
   iptables -S
   cat  > /lib/dhcpcd/dhcpcd-hooks/70-ipv4.nat <<EOF
iptables-restore < /etc/iptables.ipv4.nat
EOF

fi

systemctl daemon-reload
service hostapd start
service dnsmasq start

echo "Test if $PKGLIST services have been started."
for pkg_name in `echo ${PKGLIST}` ; do

   systemctl is-active $pkg_name >/dev/null
   if [ "$?" = "0" ] ; then
      echo "$pkg_name is running"
   else
      echo "$pkg_name is NOT running"
   fi
done

exit 0

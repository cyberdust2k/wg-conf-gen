#!/bin/bash
# wg-conf-gen
# automates generating wireguard peer configs.
# ---

# user defined vars
# --------------------------------------
# specify listen port here, usually 51820
port=""
# specify endpoint domain here (domain.example.com)
domain=""
# specify DNS (IPv4, IPv6 (optional))
dns=""
# specify second IP block (10.xxx.0.0/24)
ipblock=""
# specify local IP range (192.168.178.0/24)
localip=""
# which network device should be used? (ip addr, usually the one with the IP specified in "localip")
netdev=""
# -----------------END------------------

# Prerequisite check
if [ "$EUID" -ne 0 ]
  then
	  echo "Please run as root"
  exit
fi

# fetch arguments, if existing
while getopts "?ln:" opt; do
  case $opt in
     l)
       l_set=1
       ;;
     n)
       conf=$OPTARG >&2
       ;;
     ?)
       echo "-l: create peer in local mode"
       echo "-n <name>: specify config name. Default is 'wg0'"
       exit
       ;;
  esac
done

# use wg0 if no config name specified
if [ -z "$conf" ]
  then
	  conf=wg0
  else 
	  :
fi

# check if local mode is desired
if [ -z $l_set ]
  then 
	AllowIP="0.0.0.0/0, ::/0"
  else 
	AllowIP="10.$ipblock.0.1/32, $localip, fc00:$ipblock:0:0::1/128, fd00::/64"
fi

# detect if config exists, prompt for creation
if [ ! -f "/etc/wireguard/$conf.conf" ]
  then
	  echo "wireguard config $conf.conf doesn't exist, create? (Y/N): "; read confirm
	  if [[ $confirm == [yY] ]]
	    then
		    serverprivkey=$(wg genkey)
		    serverpubkey=$(echo $serverprivkey | wg pubkey)
		    umask 077
		    touch /etc/wireguard/$conf.conf
		    echo "[Interface]" >> /etc/wireguard/$conf.conf
		    echo "PrivateKey=$serverprivkey" >> /etc/wireguard/$conf.conf
		    echo "Address=10.$ipblock.0.1, fc00:$ipblock:0:0::1" >> /etc/wireguard/$conf.conf
		    echo "ListenPort=$port" >> /etc/wireguard/$conf.conf
		    echo "PostUp=logger -t wireguard 'Tunnel WireGuard-$conf started'" >> /etc/wireguard/$conf.conf
		    echo "PostUp=iptables -t nat -A POSTROUTING -s 10.$ipblock.0.0/24 -o $netdev -j MASQUERADE" >> /etc/wireguard/$conf.conf
		    echo "PostUp=ip6tables -t nat -A POSTROUTING -s fc00:$ipblock:0:0::/64 -o $netdev -j MASQUERADE" >> /etc/wireguard/$conf.conf
		    echo "PostDown=logger -t wireguard 'Tunnel WireGuard-$conf stopped'" >> /etc/wireguard/$conf.conf
		    echo "PostDown=iptables -t nat -D POSTROUTING -s 10.$ipblock.0.0/24 -o $netdev -j MASQUERADE" >> /etc/wireguard/$conf.conf
		    echo "PostDown=ip6tables -t nat -D POSTROUTING -s fc00:$ipblock:0:0::/64 -o $netdev -j MASQUERADE" >> /etc/wireguard/$conf.conf
		    echo "$serverpubkey" > /etc/wireguard/pubkey.$conf
		    newconf=1
	    else
		    echo "no new config will be generated, aborting..."
		    exit
	  fi
fi
	  

# boilerplate vars
serverprivkey=$(sed -n '/Interface/,/\N/p' /etc/wireguard/"$conf".conf | grep "PrivateKey" | sed "s/PrivateKey=//")
serverpubkey=$(cat /etc/wireguard/pubkey."$conf")
clientprivkey=$(wg genkey)
clientpubkey=$(echo $clientprivkey | wg pubkey)
presharedkey=$(openssl rand 32 | base64)
if [ -z $newconf ]
  then
	peercount=$(grep 'AllowedIPs' /etc/wireguard/"$conf".conf | sed "s/AllowedIPs=//" | sed -r "s/, (([[:xdigit:]]{,4}:)*)[[:xdigit:]]{,4}:[[:xdigit:]]{,4}//" | sed -r 's/(\b[0-9]{1,3}\.){2}[.0-9]{1,2}\b'// | tail -n 1)
  else
	peercount=1
fi
newpeercount=$(($peercount + 1))

# disable wireguard if necessary
wg-quick down $conf

# peer config
echo "generating config..."
sleep 1
touch /etc/wireguard/peer$(($peercount - 1)).conf
echo "[Interface]" >> /etc/wireguard/peer$(($peercount - 1)).conf
echo "PrivateKey = $clientprivkey" >> /etc/wireguard/peer$(($peercount - 1)).conf
echo "Address = 10.$ipblock.0.$newpeercount, fc00:$ipblock::$newpeercount/128" >> /etc/wireguard/peer$(($peercount - 1)).conf
echo "DNS = $dns" >> /etc/wireguard/peer$(($peercount - 1)).conf
echo "" >> /etc/wireguard/peer$(($peercount - 1)).conf
echo "[Peer]" >> /etc/wireguard/peer$(($peercount - 1)).conf
echo "PublicKey = $serverpubkey" >> /etc/wireguard/peer$(($peercount - 1)).conf
echo "PresharedKey = $presharedkey" >> /etc/wireguard/peer$(($peercount - 1)).conf
echo "AllowedIPs = $AllowIP" >> /etc/wireguard/peer$(($peercount - 1)).conf
echo "Endpoint = $domain:$port" >> /etc/wireguard/peer$(($peercount - 1)).conf

# server config
echo "appending to server config..."
sleep 1
echo "" >> /etc/wireguard/$conf.conf
echo "[Peer]" >> /etc/wireguard/$conf.conf
echo "# Auto-generated Client $(($peercount - 1))" >> /etc/wireguard/$conf.conf
echo "Publickey=$clientpubkey" >> /etc/wireguard/$conf.conf
echo "Presharedkey=$presharedkey" >> /etc/wireguard/$conf.conf
echo "AllowedIPs=10.$ipblock.0.$newpeercount, fc00:$ipblock:0:0::$newpeercount" >> /etc/wireguard/$conf.conf

# generate QR code, if qrencode is installed
if [ "$(which qrencode)" != "/usr/bin/qrencode" ]
  then
       	echo "qrencode not installed, skipping QR code generation..."
  else
        echo "generating QR code..."
        sleep 1
        qrencode -t ansiutf8 < /etc/wireguard/peer$(($peercount - 1)).conf
fi


# re-enable wireguard
wg-quick up $conf

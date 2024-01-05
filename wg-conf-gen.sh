#!/bin/bash
# wg-conf-gen (c) Dustin Stratmann 2023
# automates generating wireguard peer configs.
# ---

# user defined vars
# --------------------------------------
# specify listen port here
port=""
# specify endpoint domain here
domain=""
# specify DNS (IPv4)
dns=""
# enable IPv6 by uncommenting the variable
# ena_v6=1
# specify DNS (IPv6)
dns6=""
# specify second IP block (10.xxx.0.0/24)
ipblock=""
# specify local IP range (192.168.178.0/24)
localip=""
# which network device should be used? (ip addr, usually the one with a similar IP as specified in "localip")
netdev=""
# -----------------END------------------


# helper variables
AllowIP="0.0.0.0/0"
# Append IPv6 part to existing variable, if $ena_v6 is set
if [ -n "$ena_v6" ]
then
        AllowIP="${AllowIP}, ::/0"
fi

conf=wg0

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
       AllowIP="10.$ipblock.0.1/32, $localip"
       # Append IPv6 part to existing variable, if $ena_v6 is set
       if [ -n "$ena_v6" ]
       then
               AllowIP="${AllowIP}, fc00:$ipblock:0:0::1/128, fd00::/64"
       fi
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

# detect if config exists, prompt for creation
if [ ! -f "/etc/wireguard/$conf.conf" ]
  then
          echo "wireguard config $conf.conf doesn't exist, create? (Y/N): "; read -r confirm
          if [[ $confirm == [yY] ]]
            then
                    serverprivkey=$(wg genkey)
                    serverpubkey=$(echo "$serverprivkey" | wg pubkey)
                    umask 077
                    touch /etc/wireguard/"$conf".conf
                    if [ -n "$ena_v6" ] # dual stack config
                    then
                        {
                                echo "[Interface]"
                                echo "PrivateKey=$serverprivkey"
                                echo "Address=10.$ipblock.0.1, fc00:$ipblock:0:0::1"
                                echo "ListenPort=$port"
                                echo "PostUp=logger -t wireguard 'Tunnel WireGuard-$conf started'"
                                echo "PostUp=iptables -t nat -A POSTROUTING -s 10.$ipblock.0.0/24 -o $netdev -j MASQUERADE"
                                echo "PostUp=ip6tables -t nat -A POSTROUTING -s fc00:$ipblock:0:0::/64 -o $netdev -j MASQUERADE"
                                echo "PostDown=logger -t wireguard 'Tunnel WireGuard-$conf stopped'"
                                echo "PostDown=iptables -t nat -D POSTROUTING -s 10.$ipblock.0.0/24 -o $netdev -j MASQUERADE"
                                echo "PostDown=ip6tables -t nat -D POSTROUTING -s fc00:$ipblock:0:0::/64 -o $netdev -j MASQUERADE"
                        }  >> /etc/wireguard/"$conf".conf
                        echo "$serverpubkey" > /etc/wireguard/pubkey."$conf"
                        newconf=1
                    else # ipv4 only config
                        {
                                echo "[Interface]"
                                echo "PrivateKey=$serverprivkey"
                                echo "Address=10.$ipblock.0.1"
                                echo "ListenPort=$port"
                                echo "PostUp=logger -t wireguard 'Tunnel WireGuard-$conf started'"
                                echo "PostUp=iptables -t nat -A POSTROUTING -s 10.$ipblock.0.0/24 -o $netdev -j MASQUERADE"
                                echo "PostDown=logger -t wireguard 'Tunnel WireGuard-$conf stopped'"
                                echo "PostDown=iptables -t nat -D POSTROUTING -s 10.$ipblock.0.0/24 -o $netdev -j MASQUERADE"
                        }  >> /etc/wireguard/"$conf".conf        
                        echo "$serverpubkey" > /etc/wireguard/pubkey."$conf"
                        newconf=1
                    fi

            else
                    echo "no new config will be generated, aborting..."
                    exit
          fi
fi


# key generation comes here
serverprivkey=$(sed -n '/Interface/,/\N/p' /etc/wireguard/"$conf".conf | grep "PrivateKey" | sed "s/PrivateKey=//")
serverpubkey=$(cat /etc/wireguard/pubkey."$conf")
clientprivkey=$(wg genkey)
clientpubkey=$(echo "$clientprivkey" | wg pubkey)
presharedkey=$(openssl rand 32 | base64)
if [ -z "$newconf" ]
  then # if peers exist, iterate number from there by counting IPs from server config
        peercount=$(grep 'AllowedIPs' /etc/wireguard/"$conf".conf | sed "s/AllowedIPs=//" | sed -r "s/, (([[:xdigit:]]{,4}:)*)[[:xdigit:]]{,4}:[[:xdigit:]]{,4}//" | sed -r 's/(\b[0-9]{1,3}\.){2}[.0-9]{1,2}\b'// | tail -n 1)
  else
        peercount=1
fi
newpeercount=$((peercount + 1))

# disable wireguard if necessary
wg-quick down "$conf"

# peer config
echo "generating config..."
sleep 1
touch /etc/wireguard/peer$((peercount - 1)).conf
if [ -n "$ena_v6" ] # dual stack config
then
{
        echo "[Interface]" 
        echo "PrivateKey = $clientprivkey"
        echo "Address = 10.$ipblock.0.$newpeercount, fc00:$ipblock::$newpeercount/128"
        echo "DNS = $dns, $dns6"
        echo ""
        echo "[Peer]"
        echo "PublicKey = $serverpubkey"
        echo "PresharedKey = $presharedkey"
        echo "AllowedIPs = $AllowIP"
        echo "Endpoint = $domain:$port"
} >> /etc/wireguard/peer$((peercount - 1)).conf
else # ipv4 only config
{
        echo "[Interface]"
        echo "PrivateKey = $clientprivkey"
        echo "Address = 10.$ipblock.0.$newpeercount"
        echo "DNS = $dns"
        echo ""
        echo "[Peer]"
        echo "PublicKey = $serverpubkey"
        echo "PresharedKey = $presharedkey"
        echo "AllowedIPs = $AllowIP"
        echo "Endpoint = $domain:$port"
} >> /etc/wireguard/peer$((peercount - 1)).conf
fi

# server config
echo "appending to server config..."
sleep 1
{
        echo ""
        echo "[Peer]"
        echo "# Auto-generated Client $((peercount - 1))"
        echo "Publickey=$clientpubkey"
        echo "Presharedkey=$presharedkey"   
} >> /etc/wireguard/"$conf".conf

if [ -n "$ena_v6" ] # dual stack config
then
        echo "AllowedIPs=10.$ipblock.0.$newpeercount, fc00:$ipblock:0:0::$newpeercount" >> /etc/wireguard/"$conf".conf
else # ipv4 only config
        echo "AllowedIPs=10.$ipblock.0.$newpeercount" >> /etc/wireguard/"$conf".conf
fi

# generate QR code, if possible
if [ "$(which qrencode)" != "/usr/bin/qrencode" ]
  then
        echo "qrencode not installed, skipping QR code generation..."
  else
        echo "generating QR code..."
        sleep 1
        qrencode -t ansiutf8 < /etc/wireguard/peer$((peercount - 1)).conf
fi

# re-enable wireguard
wg-quick up "$conf"

#!/bin/bash

#export serverIP="<PUBLIC_IP_OF_YOUR_SERVER>" 
export serverIP=$1
# List of clietns you want to create
declare -a clients=(
"iphone" 
"andriod"
"ipad"
"fire-tv" 
"home-laptop" 
"windows-laptop"
"macbook" 
"pi"
#...so on
)

keyGen(){
    client="$1"
    wg genkey | tee keys/${client}_private_key | wg pubkey > keys/${client}_public_key
}

getPeers(){
peers=""
index=1
for c in "${clients[@]}" 
 do 
    index=$((index+1))
    ckey="$(cat keys/${c}_public_key)"         
    peers+="
[Peer] # ${c}
PublicKey = ${ckey}
AllowedIPs = 10.200.200.${index}/32

"    
done
echo "$peers"    
}

clientConfigGen(){
peers=""
index=1
for c in "${clients[@]}" 
 do 
    index=$((index+1))
    cpkey="$(cat keys/${c}_private_key)"
    echo "
[Interface] 
Address = 10.200.200.${index}/32
PrivateKey = ${cpkey}
DNS = 10.200.200.1 

[Peer]
PublicKey = $(cat 'keys/server_public_key')
Endpoint = ${serverIP}:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 21" >  clients/${c}.conf  

qrencode -o clients/${c}.png -t png < clients/${c}.conf    
done 
}

# Start Script execution  
rm -rf keys clients 
mkdir keys
mkdir clients 

#installs
sudo apt update -y   
#sudo apt upgrade -y -qq
sudo apt install wireguard linux-headers-$(uname -r) -y  
sudo apt install qrencode -y
sudo apt install iptables-persistent -y
sudo apt install unbound unbound-host -y

# Generate keys
keyGen "server"
for c in "${clients[@]}" 
 do
 keyGen $c 
done

# Generate server config
echo " 
[Interface]
PrivateKey = $(cat keys/server_private_key)
Address = 10.200.200.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o ens3 -j MASQUERADE; iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o ens3 -j MASQUERADE; iptables -t nat -D POSTROUTING -s 10.200.200.0/24 -o eth0 -j MASQUERADE
SaveConfig = true
$(getPeers)
" |  tee clients/wg0.conf 
cat clients/wg0.conf | sudo tee /etc/wireguard/wg0.conf 

#Generate clients configs
clientConfigGen

# Firewall 

#Track VPN connection
sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
#VPN traffic on the listening port
sudo iptables -A INPUT -p udp -m udp --dport 51820 -m conntrack --ctstate NEW -j ACCEPT
#TCP and UDP recursive DNS traffic
sudo iptables -A INPUT -s 10.200.200.0/24 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A INPUT -s 10.200.200.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
#Allow forwarding of packets that stay in the VPN tunnel
sudo iptables -A FORWARD -i wg0 -o wg0 -m conntrack --ctstate NEW -j ACCEPT


# enable IPv4 forwarding
sudo sed -i 's/\#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf

#DNS
# download list of DNS root servers
sudo curl -o /var/lib/unbound/root.hints https://www.internic.net/domain/named.cache

# create Unbound config file
echo "
server:
    num-threads: 4
    # enable logs
    verbosity: 1
    # list of root DNS servers
    root-hints: \"/var/lib/unbound/root.hints\"
    # use the root server's key for DNSSEC
    auto-trust-anchor-file: \"/var/lib/unbound/root.key\"
    # respond to DNS requests on all interfaces
    interface: 0.0.0.0
    max-udp-size: 3072
    # IPs authorised to access the DNS Server
    access-control: 0.0.0.0/0                 refuse
    access-control: 127.0.0.1                 allow
    access-control: 10.200.200.0/24             allow
    # not allowed to be returned for public Internet  names
    private-address: 10.200.200.0/24
    #hide DNS Server info
    hide-identity: yes
    hide-version: yes
    # limit DNS fraud and use DNSSEC
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-referral-path: yes
    # add an unwanted reply threshold to clean the cache and avoid, when possible, DNS poisoning
    unwanted-reply-threshold: 10000000
    # have the validator print validation failures to the log
    val-log-level: 1
    # minimum lifetime of cache entries in seconds
    cache-min-ttl: 1800
    # maximum lifetime of cached entries in seconds
    cache-max-ttl: 14400
    prefetch: yes
    prefetch-key: yes

" | sudo tee /etc/unbound/unbound.conf 

# give root ownership of the Unbound config
sudo chown -R unbound:unbound /var/lib/unbound


echo "127.0.0.1 $(hostname)" | sudo tee -a /etc/hosts

export DEBIAN_FRONTEND=noninteractive

# services
sudo systemctl enable wg-quick@wg0.service
sudo systemctl enable netfilter-persistent  
sudo netfilter-persistent save

# disable systemd-resolved
sudo systemctl stop systemd-resolved &&
sudo systemctl disable systemd-resolved

# enable Unbound in place of systemd-resovled
sudo systemctl enable unbound-resolvconf &&
sudo systemctl enable unbound

sudo reboot

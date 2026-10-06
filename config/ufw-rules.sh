#!/bin/bash
# Regles UFW a appliquer sur srv-backup
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.10 to any port 22 proto tcp comment 'SSH depuis srv-principal'
sudo ufw enable
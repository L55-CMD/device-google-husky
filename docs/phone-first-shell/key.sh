#!/bin/sh
mkdir -p /home/phablet/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFIqSkGvbpj4d5idoMT5PxRDieDIClDZRAUMIFhBFLMg husky-bringup-20261113" > /home/phablet/.ssh/authorized_keys
chown -R 32011:32011 /home/phablet/.ssh
chmod 700 /home/phablet/.ssh
chmod 600 /home/phablet/.ssh/authorized_keys
echo KEY-INSTALLED

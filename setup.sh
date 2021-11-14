#!/bin/bash


function main() {
    sudo yum install httpd -y                  >> $${LOG}
	sudo yum install mod_wsgi -y               >> $${LOG}
	# Tricky to log this
	sudo echo "LoadModule wsgi_module modules/mod_wsgi.so" >> /etc/httpd/conf/httpd.conf
	# System Manager - But you need a whole pile of policy crap - not bothering for now
	# https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-ug.pdf#systems-manager-quick-setup
	#sudo yum install -y https://s3.ap-southeast-2.amazonaws.com/amazon-ssm-ap-southeast-2/latest/linux_amd64/amazon-ssm-agent.rpm -y
	#
	sudo yum install git -y                    >> $${LOG}
	# get CTFd
	
	export APPDIR=/home/ec2-user/app           >> $${LOG}
	mkdir -p $${APPDIR}                        >> $${LOG}
	git clone https://github.com/CTFd/CTFd.git >> $${LOG}
	# Create a random key
	cd CTFd                                    >> $${LOG}
	head -c 64 /dev/urandom > .ctfd_secret_key >> $${LOG}
	
    #sudo systemctl enable httpd >> $${LOG}
    #sudo systemctl start httpd >> $${LOG}
    #echo "<html><body><div>Hello, world!</div></body></html>" > /var/www/html/index.html
}
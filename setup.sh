#!/usr/bin/bash


function main() {
    echo "Installing Apache"
    sudo yum install httpd -y 
    echo "Installing mod_wsgi"	
	sudo yum install mod_wsgi -y 
	

	echo " Add mod_wsgi.so to the Apache config"
	sudo echo "LoadModule wsgi_module modules/mod_wsgi.so" >> /etc/httpd/conf/httpd.conf
	
	# System Manager - But you need a whole pile of policy crap - not bothering for now
	# https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-ug.pdf#systems-manager-quick-setup
	#sudo yum install -y https://s3.ap-southeast-2.amazonaws.com/amazon-ssm-ap-southeast-2/latest/linux_amd64/amazon-ssm-agent.rpm -y
	#
	# Git is already installed, else how did we get here?
	# sudo yum install git -y   

	
	# get CTFd
	echo "Get CTFd"
	export APPDIR=/home/ec2-user/app           
	mkdir -p ${APPDIR}                        
	git clone https://github.com/CTFd/CTFd.git 
	
	# Create a random key
	cd CTFd                                    
	head -c 64 /dev/urandom > .ctfd_secret_key 
	
    #sudo systemctl enable httpd >> $${LOG}
    #sudo systemctl start httpd >> $${LOG}
    #echo "<html><body><div>Hello, world!</div></body></html>" > /var/www/html/index.html
}

main 
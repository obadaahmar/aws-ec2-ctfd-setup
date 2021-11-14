#!/usr/bin/bash


function main() {
	logger -s "Installing Apache"
	sudo yum install httpd -y 
	
	logger -s "Installing mod_wsgi"
	sudo yum install mod_wsgi -y 
	
	logger -s "Add mod_wsgi.so to the Apache config"
	sudo echo "LoadModule wsgi_module modules/mod_wsgi.so" >> /etc/httpd/conf/httpd.conf
	
	# System Manager - But you need a whole pile of policy crap - not bothering for now
	# https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-ug.pdf#systems-manager-quick-setup
	#sudo yum install -y https://s3.ap-southeast-2.amazonaws.com/amazon-ssm-ap-southeast-2/latest/linux_amd64/amazon-ssm-agent.rpm -y
	#
	# Git is already installed, else how did we get here?
	# sudo yum install git -y   

	
	# get CTFd

	export APPDIR=${HOME}/app      
    export TARGET="https://github.com/CTFd/CTFd.git"
	mkdir -p ${APPDIR}  
    cd ${APPDIR}	
	logger -s "Clone CTFd from ${TARGET}, save into ${APPDIR}"
	git clone $TARGET
	
	# Create a random key
	cd CTFd   
    logger -s "pwd=`pwd`"
    logger -s "Create .ctfd_secret_key"	
	head -c 64 /dev/urandom > .ctfd_secret_key 

	
	#dummy homepage
    echo "<html><body><div>Hello, world!</div></body></html>" > /var/www/html/index.html
	
		
	logger -s "Enable httpd"
    sudo systemctl enable httpd
    logger -s "Start https"	
    sudo systemctl start httpd 
}

main 
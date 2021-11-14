#!/usr/bin/bash


function root_pre() {
	# Steps to run as root prior to main
	logger -s "Installing Apache"
	sudo yum install httpd -y 
	
	logger -s "Installing mod_wsgi"
	sudo yum install mod_wsgi -y 
	
	# Git is already installed, else how did we get here?
	# sudo yum install git -y   
		
	logger -s "Add mod_wsgi.so to the Apache config"

	sudo echo "LoadModule wsgi_module modules/mod_wsgi.so" >> /etc/httpd/conf.d/wsgi.conf
	
}

function root_post() {
	# Steps to run as root after main
	#dummy homepage
	
	echo "<html><body><div>Hello, world\!</div></body></html>" > index.html
	sudo mv index.html > /var/www/html/index.html
	
		
	logger -s "Enable httpd"
	sudo systemctl enable httpd
	
	logger -s "Start httpd"	
	sudo systemctl start httpd 
}


function main() {

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
	
	

}

case $1 in
	"pre"*)
		root_pre
		;;
	"post"*)
		root_post
		;;
	"main"*)
		main
		;;
	*)
		main
		;;
esac

echo "Done"

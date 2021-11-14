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
	cd html
	logger -s "Installing mysql"
	sudo yum install mysql -y
}

function root_post() {
	# Steps to run as root after main
	#dummy homepage
	
	echo "<html><body><div>Hello, world</div></body></html>" > /var/www/html/index.html
	
	cat <<EOF > /var/www/html/ctf.wsgi
import sys
sys.path.insert(0, '/var/www/html')

from CTFd import create_app
application = create_app()

EOF
	cat <<EOF > /etc/httpd/conf.d/ctfd.conf
<VirtualHost *:80>
    ServerName ctfd.wonkie.cloud
    ServerAlias www.myserver.com
    DocumentRoot /var/www/html

    WSGIScriptAlias / /var/www/html/ctf.wsgi
    WSGIDaemonProcess ctfd user=ctfd group=ctfd threads=5
    WSGIProcessGroup ctfd

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined


    #Alias /static/ /var/www/FLASKAPPS/helloworldapp/static
    <Directory /var/www/html/CTFd>
        Order allow,deny
        Allow from all
    </Directory>
</VirtualHost>

EOF
	
	
	#cd /var/www/html/
	ln -s /home/ctfd/app/CTFd/ /var/www/html/CTFd

		
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

#!/usr/bin/bash




function root_pre() {
    SVC=${1}
	# Steps to run as root prior to main
	logger -s "Installing Apache"
	sudo yum install httpd -y

	logger -s "Installing mod_wsgi"
	#sudo yum install mod_wsgi -y
	sudo yum install python3-mod_wsgi -y


	# Git is already installed, else how did we get here?
	# sudo yum install git -y

	logger -s "Add mod_wsgi.so to the Apache config"

	sudo echo "LoadModule wsgi_module modules/mod_wsgi.so" >> /etc/httpd/conf.d/wsgi.conf
	
	logger -s "Installing mysql"
	sudo yum install mysql -y
}

function root_post() {

    SVC=${1}
	# Steps to run as root after main
	#dummy homepage
	APACHE_LOG_DIR=/var/log/httpd
	echo "<html><body><div>If everything works, you shouldn't see this</div></body></html>" > /var/www/html/index.html

    # Write the virtual host to run this site (port 80 - dodgy)
	logger -s "Write /etc/httpd/conf.d/ctfd.conf"
	
	cat <<EOF > /etc/httpd/conf.d/ctfd.conf
<VirtualHost *:80>
    ServerName ctfd.wonkie.cloud
    ServerAlias www.myserver.com
    DocumentRoot /home/ctfd/app/CTFd


    WSGIScriptAlias / /home/${SVC}/app/ctf.wsgi
    WSGIDaemonProcess ${SVC} user=${SVC} group=${SVC} threads=5
    WSGIProcessGroup ${SVC}


    ErrorLog ${APACHE_LOG_DIR}/error_log
    CustomLog ${APACHE_LOG_DIR}/access_log combined


    #Alias /static/ /var/www/FLASKAPPS/helloworldapp/static
    <Directory /home/ctfd/app>
        Order allow,deny
        Allow from all
		Options Indexes MultiViews
        AllowOverride None
        Require all granted

    </Directory>

</VirtualHost>

EOF


	#cd /var/www/html/
	#ln -s /home/ctfd/app/ctfd/ /var/www/html/CTFd/CTFd
    #ln -s /home/ctfd/app/CTFd/CTFd /var/www/html/CTFd
    
	# Install flask
    #sudo pip3 install flask
	
	logger -s "Enable httpd as a service"
	sudo systemctl enable httpd

	logger -s "Start httpd service"
	sudo systemctl start httpd
}


function main() {
    SVC=${1}
    # permit Apache to read from Service Account when running as root
	logger -s "Ensure httpd can read from Service Account"
	chmod og+rx ${HOME}


	# get CTFd from GitHub
    logger -s "Fetch CTFd from https://github.com/CTFd/CTFd.git"
	export APPDIR=${HOME}/app
	export TARGET="https://github.com/CTFd/CTFd.git"
	mkdir -p ${APPDIR}
	cd ${APPDIR}
	logger -s "Clone CTFd from ${TARGET}, save into ${APPDIR}"
	git clone $TARGET

	# Create a random key
	logger -s "Randomise a key"
	cd CTFd
	logger -s "pwd=`pwd`"
	logger -s "Create .ctfd_secret_key"
	head -c 64 /dev/urandom > .ctfd_secret_key
    
	logger -s "Update python modules used by CTFd"
	# Update the Python Modules
	pip3 install -r requirements.txt


    # Write the .wsgi file than gets executed when you hit the website
	# Include /usr/local/bin ( why? )
	logger -s "Configure ctfd.wsgi"
	cat <<EOF > ${APPDIR}/ctf.wsgi
import sys
sys.path.insert(0, '/usr/local/bin')
sys.path.insert(0, '${APPDIR}/CTFd')

from CTFd import create_app
application = create_app()


EOF

}

$SVC=${2:=ctfd}
logger -s "setup.sh: $1 $2 (SVC=${SVC})"
case $1 in
	"pre"*)
		root_pre $SVC
		;;
	"post"*)
		root_post $SVC
		;;
	"main"*)
		main $SVC
		;;
	*)
		main
		;;
esac
logger -s "setup.sh: done"
echo "Done"

#!/usr/bin/bash




function root_pre() {
    SVC=${1}
	# Steps to run as root prior to main
	logger -s "Installing Apache"
	sudo yum install httpd -y

	logger -s "Installing mod_wsgi"
	#sudo yum install mod_wsgi -y
	sudo yum install python3-mod_wsgi -y


	# Git is already installed, else how did we get here? Well, just in case...
	sudo yum install git -y

    # Apache needs to load mod_wsgi.so in order to run python wsgi
	logger -s "Add mod_wsgi.so to the Apache config"
	sudo echo "LoadModule wsgi_module modules/mod_wsgi.so" >> /etc/httpd/conf.d/wsgi.conf
	
	# we want to use mariadb10.5 so we need to enable it
	# https://aws.amazon.com/premiumsupport/knowledge-center/ec2-install-extras-library-software/
	# sudo yum install -y amazon-linux-extras
	sudo amazon-linux-extras enable mariadb10.5
	sudo yum clean metadata
	
	logger -s "Installing mysql (mariadb)"
	sudo yum install mariadb -y
	sudo systemctl enable mariadb
    sudo systemctl start mariadb
	
	echo "mysql version: `mysql --version`"
    logger -s "Setup and secure Mysql/MariaDB"
	
	#NB: MariaDB 10 has an extra Yes needed before the password change (remove one if you're using v5.5)
    sudo mysql_secure_installation <<EOF

y
y
secret$SVC
secret$SVC
y
y
y
y
EOF

    logger -s "Install redis"
    sudo amazon-linux-extras enable redis6
    sudo yum clean metadata
	sudo yum install redis -y
	
	CONFIG=/etc/redis/redis.conf
	# Need to provide a config
    # TODO: /etc/redis/redis.conf
	# https://raw.githubusercontent.com/redis/redis/6.2/redis.conf
	# 
	# Default config is 
	#   bind 127.0.0.1 -::1
	#   protected-mode yes
	#   port 6379
	# We'll use an ACL file to specify users
	
	logger -s "Update the Redis config file $CONFIG: configure REDIS to use ACL file"
	# Uncomment the aclfile entry
	sed -i "s|# aclfile /etc/redis/users.acl|aclfile /etc/redis/users.acl|g" $CONFIG
	# Genreate a redis.acl file, include use ctfd, permission for all, password as defined
	cat <<EOF > /etc/redis/users.aclfile

user ctfd on +@all -DEBUG ~* >secret$SVC
EOF

	logger -s "Enable redis as a service"
	sudo systemctl enable redis
	
	logger -s "Start redis service"
    sudo systemctl start redis
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
    DocumentRoot /home/${SVC}/app/CTFd


    WSGIScriptAlias / /home/${SVC}/app/ctf.wsgi
    WSGIDaemonProcess ${SVC} user=${SVC} group=${SVC} threads=5 home=/home/${SVC}/app/CTFd
    WSGIProcessGroup ${SVC}


    ErrorLog ${APACHE_LOG_DIR}/error_log
    CustomLog ${APACHE_LOG_DIR}/access_log combined


    <Directory /home/${SVC}/app>
        Order allow,deny
        Allow from all
		Options Indexes MultiViews
        AllowOverride None
        Require all granted
    </Directory>

</VirtualHost>

EOF

	
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
	logger -s "Create .ctfd_secret_key in `pwd`"
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

    logger -s "Update the CTFd config file"
    # Update the config file
	CONFIG=${APPDIR}/CTFd/CTFd/config.ini
	
	logger -s "Update the CTFd config file $CONFIG: configure DB"
	# Replace the Database String
	sed -i "s|DATABASE_URL =|DATABASE_URL = mysql+pymysql://root:secret$SVC@localhost/ctfd|g" $CONFIG
	
	logger -s "Update the CTFd config file $CONFIG: configure REDIS"
	# Replace the Database String
	sed -i "s|REDIS_URL =|REDIS_URL = redis://ctfd:secret$SVC@localhost:6379|g" $CONFIG
	
	logger -s "Initialise the DB"
	python3 manage.py db upgrade
	
}

SVC=${2:-ctfd}
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

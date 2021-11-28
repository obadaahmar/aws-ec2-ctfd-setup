#!/usr/bin/bash

# Wrapper for logger to provide some highlight
function headline_logger () {
  MSG=$2
  echo "******************************************************************************************"
  /bin/logger -s ${2}
  echo "******************************************************************************************"
}

# Root commands - pre service account, fetch packages, configure DB & Caching Server
function root_pre() {
    SVC=${1}
	headline_logger -s "Start ${0} installation as `whoami`"

	
	
	# Steps to run as root prior to main
	headline_logger -s "Installing Apache"
	sudo yum install httpd -y
	
	
	#headline_logger -s "Installing mod_wsgi"
	#sudo yum install mod_wsgi -y           # No good, this is for python 2
	#sudo yum install python3-mod_wsgi -y   # No good, this is mod_wsgi v 3.4, we want 4.x

	# Do it the hard way: https://pypi.org/project/mod-wsgi/
	headline_logger -s "Installing Developer Tools"
	sudo yum groupinstall "Development Tools" -y
	
	#headline_logger -s "Installing Apache Devel"
	#sudo yum install httpd-devel -y         # so, we need httpd-devel
	
	headline_logger -s "Installing mod wsgi 4.x"
	curl https://files.pythonhosted.org/packages/b6/54/4359de02da3581ea4a17340d87fd2c5a47adc4c8e626f9809e2697b2d33f/mod_wsgi-4.9.0.tar.gz --output mod_wsgi-4.9.0.tar.gz
	tar -xzvf mod_wsgi-4.9.0.tar.gz
    cd mod_wsgi-4.9.0
	./configure
	make
	make install
	# python setup.py install


	# Git is already installed, else how did we get here? Well, just in case...
	headline_logger -s "Installing git"
	sudo yum install git -y

    # Apache needs to load mod_wsgi.so in order to run python wsgi
	logger -s "Add mod_wsgi.so to the Apache config"
	sudo echo "LoadModule wsgi_module modules/mod_wsgi.so" >> /etc/httpd/conf.d/wsgi.conf
	
	# we want to use mariadb10.5 so we need to enable it
	# https://aws.amazon.com/premiumsupport/knowledge-center/ec2-install-extras-library-software/
	# sudo yum install -y amazon-linux-extras
	headline_logger -s "Enable MariaDB v10.5"
	sudo amazon-linux-extras enable mariadb10.5
	sudo yum clean metadata
	
	headline_logger -s "Installing mysql (MariaDB)"
	sudo yum install mariadb -y
	logger -s "Enable MariaDB as a service"
	sudo systemctl enable mariadb
	logger -s "Start MariaDB service"
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

    headline_logger -s "Enable redis6"
    sudo amazon-linux-extras enable redis6
    sudo yum clean metadata
	
	headline_logger -s "Installing redis"
	sudo yum install redis -y
	
	CONFIG=/etc/redis/redis.conf
	# Need to provide a config
	#  /etc/redis/redis.conf
	# https://raw.githubusercontent.com/redis/redis/6.2/redis.conf
	# 
	# Default config is 
	#   bind 127.0.0.1 -::1
	#   protected-mode yes
	#   port 6379
	# This is fine, but we'll use an ACL file to specify users
	
	logger -s "Update the Redis config file $CONFIG: configure REDIS to use ACL file"
	# Uncomment the aclfile entry
	sed -i "s|# aclfile /etc/redis/users.acl|aclfile /etc/redis/users.acl|g" $CONFIG
	# Genreate a redis.acl file, include use ctfd, permission for all, password as defined
	cat <<EOF > /etc/redis/users.acl
user ctfd on +@all -DEBUG ~* >secret$SVC
EOF

	logger -s "Enable redis as a service"
	sudo systemctl enable redis	
	logger -s "Start redis service"
    sudo systemctl start redis
	
	
#	headline_logger -s "Configuring this host to use python 3.7"
#	sudo alternatives --set python /usr/bin/python3.7
	# doesn't work so well
#	logger -s "python version: `python --version`"
    
	# the hard way
#	cd /usr/bin
#	logger -s "old: `ls -al python`"
#	sudo rm -f python
#	sudo ln -s python3 python
#	logger -s "new: `ls -al python`"
#	logger -s "python version: `python --version`"
	
	#/usr/sbin/httpd -X -e debug

}

# Root commands - post service account, configure and start apache
function root_post() {
    SVC=${1}
	headline_logger -s "Start ${0} installation as `whoami`"
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
    DocumentRoot /home/${SVC}/app


    WSGIScriptAlias / /home/${SVC}/app/ctf.wsgi
    WSGIDaemonProcess ${SVC} user=${SVC} group=${SVC} processes=5 threads=15 home=/home/${SVC}/app/CTFd
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

# SVC commands - run as unpriv user, install main application
function main() {
    headline_logger -s "Start ${0} installation as `whoami`"
    SVC=${1}
	
    # permit Apache to read from Service Account when running as root
	logger -s "Ensure httpd can read from Service Account"
	chmod og+rx ${HOME}

	# get CTFd from GitHub   
	export APPDIR=${HOME}/app
	export TARGET="https://github.com/CTFd/CTFd.git"
	mkdir -p ${APPDIR}
	cd ${APPDIR}
	headline_logger -s "Clone CTFd from ${TARGET}, save into ${APPDIR}"
	git clone $TARGET

	# Create a random key
	logger -s "Randomise a key"
	cd CTFd
	#logger -s "pwd=`pwd`"
	#logger -s "Create .ctfd_secret_key in `pwd`"
	#head -c 64 /dev/urandom > .ctfd_secret_key
    
	logger -s "Update python modules used by CTFd"
	
	# Update the Python Modules
	pip3 install -r requirements.txt


    # Write the .wsgi file than gets executed when you hit the website
	# Include /usr/local/bin ( why? )
	logger -s "Configure ctfd.wsgi"
	cat <<EOF > ${APPDIR}/ctf.wsgi
import sys
sys.path.insert(0, '${APPDIR}/CTFd')

from CTFd import create_app
application = create_app()


EOF

    logger -s "Update the CTFd config file"
    # Update the config file
	CONFIG=${APPDIR}/CTFd/CTFd/config.ini


	# Define the Secret Key	

	logger -s "Update the CTFd config file $CONFIG: configure SECRET_KEY"
	sed -i "s|# SECRET_KEY =|SECRET_KEY = ${SVC}s3cr3t${SVC}123|g" $CONFIG
	
	# Define the Database String	
	logger -s "Update the CTFd config file $CONFIG: configure DB"
	sed -i "s|DATABASE_URL =|DATABASE_URL = mysql+pymysql://root:secret$SVC@localhost/ctfd|g" $CONFIG
	
	# Define the Cache Server String	
#	logger -s "Update the CTFd config file $CONFIG: configure REDIS"
#	sed -i "s|REDIS_URL =|REDIS_URL = redis://ctfd:secret$SVC@localhost:6379|g" $CONFIG
	
	# Define the Application root	
	# APPLICATION_ROOT = /home/ctfd/app/CTFd
	logger -s "Update the CTFd config file $CONFIG: configure APPLICATION_ROOT"
	sed -i "s|# APPLICATION_ROOT =| APPLICATION_ROOT = / |g" $CONFIG

	headline_logger -s "Check the DB is available"
	python3 ping.py

	headline_logger -s "Initialise the DB"
	python3 manage.py db upgrade
	
}

SVC=${2:-ctfd}
headline_logger -s "setup.sh: $1 $2 (SVC=${SVC})"
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
headline_logger -s "setup.sh: done"
echo "Done"

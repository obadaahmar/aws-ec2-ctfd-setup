#!/usr/bin/bash
#
# aws-ecw-ctfd-setup
#
# build a CTFd instance for capture the flag competitions
#

# Wrapper for logger to provide some highlight
function headline_logger () {
  MSG=$2
  echo "*********************************************************************************************"
  /bin/logger -s ${2}
  echo "*********************************************************************************************"
}

# Root commands - pre service account, fetch packages, configure DB & Caching Server
function root_pre() {
  SVC=${1}
  headline_logger -s "Start ${0} installation as `whoami`"
  logger -s "pwd=`pwd`"

  # Disable SELinux to do the install
  CONFIG=/etc/selinux/config
  logger -s "Update the SELinux config file $CONFIG: configure SELINUX=permissive"
  sed -i "s|SELINUX=enforcing|SELINUX=permissive|g" $CONFIG
  #sed -i "s|SELINUX=enforcing|SELINUX=disabled|g" $CONFIG
  # Disable immediately
  setenforce 0

  # Install semanage to grant the permissions at the end of the build
  headline_logger -s "Installing semanage"
  sudo yum install /usr/sbin/semanage -y



  # Git is already installed, else how did we get here? Well, just in case...
  headline_logger -s "Installing git"
  sudo yum install git -y

  #################################################################################################
  #
  #  WEB BROWSER - APACHE 2.4
  #
  #################################################################################################


  headline_logger -s "Installing Apache"
  sudo yum install httpd -y

  # Do it the hard way: https://pypi.org/project/mod-wsgi/
  headline_logger -s "Installing Developer Tools"
  sudo yum groupinstall "Development Tools" -y   # We need gcc etc ...

  headline_logger -s "Installing Apache Devel"   # We'll need axps (Apache Extension Tool) etc ...
  sudo yum install httpd-devel -y                # so, we need httpd-devel
  headline_logger -s "Installing Python Devel"
  sudo yum install python3.10 python3.10-devel -y     # changed python version

  headline_logger -s "Installing mod wsgi 5.0.0"
  curl https://github.com/GrahamDumpleton/mod_wsgi/archive/refs/tags/5.0.0.tar.gz --output mod_wsgi-5.0.0.tar.gz
  tar -xzvf mod_wsgi-5.0.0.tar.gz

  cd mod_wsgi-5.0.0
  ./configure --with-python=/bin/python3         # we'd like this compiled against python3 thanks
  make
  sudo make install

  #check diskspace
  echo "Disk space:`df -k`"

  # Shouldn't leave ggc & dev tools lying around - plus it recovers some disk space
  headline_logger -s "Uninstalling Developer Tools"
  sudo yum erase "Development Tools" -y

  headline_logger -s "Uninstalling Apache Devel"
  sudo yum erase httpd-devel -y

  # we could nuke the install package for redis as well
  echo "Disk space:`df -k`"

    # Apache needs to load mod_wsgi.so in order to run python wsgi
  logger -s "Add mod_wsgi.so to the Apache config"
  sudo echo "LoadModule wsgi_module modules/mod_wsgi.so" >> /etc/httpd/conf.d/wsgi.conf

  ################################################################################################
  #
  #  DATABASE - MARIADB
  #
  ################################################################################################

  # NOTES - it's possible that the DB isn't initialised properly

  # see vagrantinstall script


  # we want to use mariadb10.5 so we need to enable it first as AWS ECS library has v5.x by default
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

  ################################################################################################
  #
  #  CACHE - REDIS
  #
  ################################################################################################

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
  # Generate a redis.acl file, include use ctfd, permission for all, password as defined
  cat <<EOF > /etc/redis/users.acl
user ctfd on +@all -DEBUG ~* >secret$SVC
EOF

  logger -s "Enable redis as a service"
  sudo systemctl enable redis
  logger -s "Start redis service"
  sudo systemctl start redis



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

    DocumentRoot /home/${SVC}/app

    WSGIScriptAlias /hello /home/${SVC}/app/hello.wsgi
    WSGIScriptAlias / /home/${SVC}/app/ctf.wsgi
    #WSGIDaemonProcess ${SVC} user=${SVC} group=${SVC} processes=5 threads=15 home=/home/${SVC}/app/CTFd

    WSGIDaemonProcess ${SVC} user=${SVC} group=${SVC} processes=5 threads=15 home=/home/${SVC}/app/CTFd queue-timeout=45 socket-timeout=60 connect-timeout=15 request-timeout=60 inactivity-timeout=0 startup-timeout=15 deadlock-timeout=60 graceful-timeout=15 eviction-timeout=0 restart-interval=0 shutdown-timeout=5 maximum-requests=0

# https://serverfault.com/questions/844761/wsgi-truncated-or-oversized-response-headers-received-from-daemon-process
# mod_wsgi - some python C extensions are non thread-safe -- WSGIApplicationGroup %{GLOBAL} -- is the fix
# https://modwsgi.readthedocs.io/en/develop/configuration-directives/WSGIApplicationGroup.html
    WSGIApplicationGroup %{GLOBAL}
    WSGIProcessGroup ${SVC}

    ErrorLog ${APACHE_LOG_DIR}/error_log
    CustomLog ${APACHE_LOG_DIR}/access_log combined


# https://modwsgi.readthedocs.io/en/master/user-guides/configuration-guidelines.html
    <Directory /home/${SVC}/app>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
    </Directory>
</VirtualHost>

EOF


  logger -s "Enable httpd as a service"
  sudo systemctl enable httpd
  logger -s "Start httpd service"
  sudo systemctl start httpd


  headline_logger "SELinux Add context for Website"
  # Add all the files under /home/ctfd
  semanage fcontext -a -t httpd_sys_content_t "/home/ctfd(/.*)?"
  # Add the shared object (.so) libraries which need to execute
  semanage fcontext -a -t httpd_exec_t "/home/ctfd/.local/.*\.so(\..*)?"
  # Allow uploads
  semanage fcontext -a -t httpd_sys_rw_content_t "/home/ctfd/app/CTFd/CTFd/uploads(/.*)?"
  # Add connection to MariaDB
  # to avoid: avc:  denied  { name_connect } for  pid=21536 comm="httpd" dest=3306 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:mysqld_port_t:s0 tclass=tcp_socket permissive=0
  setsebool -P httpd_can_network_connect_db=1 httpd_can_network_connect=1
  # Reload the context
  restorecon -R -v /home/ctfd

  # Thanks to:
  # https://wiki.gentoo.org/wiki/SELinux/Tutorials/How_SELinux_controls_file_and_directory_accesses
  # https://serverfault.com/questions/964755/getting-compiled-python-mod-wsgi-module-working-on-apache-server-with-selinux-en
  # https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/managing_confined_services/sect-managing_confined_services-the_apache_http_server-types
  # https://bugzilla.redhat.com/show_bug.cgi?id=182346
  # and the fine manuals,...
  # https://man7.org/linux/man-pages/man8/semanage-fcontext.8.html
  #
  # Obviously, you can also turn off selinux (setenforce 0)

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
  # Drop a test in also

  cat <<EOF > ${APPDIR}/hello.wsgi
def application(environ, start_response):
    status = '200 OK'
    output = b'Hello World!'

    response_headers = [('Content-type', 'text/plain'),
                        ('Content-Length', str(len(output)))]
    start_response(status, response_headers)

    return [output]
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
  logger -s "Update the CTFd config file $CONFIG: configure REDIS"
  sed -i "s|REDIS_URL =|REDIS_URL = redis://ctfd:secret$SVC@localhost:6379|g" $CONFIG

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

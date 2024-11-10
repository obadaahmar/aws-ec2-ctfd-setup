#!/usr/bin/bash

  # Configuration variables
  LOG=/var/log/setup.log  # Log file for the setup process
  SVC=ctfd  # Service account name
  GITHUB_USER=CTFd  # GitHub username
  GITHUB_REPO=CTFd  # GitHub repository name
  SECRET_KEY=$(head -c 64 /dev/urandom | base64) # Generate a random secret key

  # Phase 1 - Basic install utils - Runs as root
  logger -s "Configuring instance (as $(whoami))" > $LOG 2>&1  # Log current user
  logger -s "pwd=$(pwd)" >> $LOG 2>&1  # Log current directory

  # Install Docker 
  logger -s "Installing Docker" >> $LOG 2>&1 
  sudo yum install -y docker >> $LOG 2>&1 
  sudo systemctl start docker >> $LOG 2>&1 
  sudo systemctl enable docker >> $LOG 

  # Install Docker Compose 
  logger -s "Installing Docker Compose" >> $LOG 2>&1 
  sudo mkdir -p /usr/local/lib/docker/cli-plugins/ >> $LOG 2>&1 
  sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose >> $LOG 2>&1 
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose >> $LOG 2>&1 

  sudo yum install git -y >> $LOG 2>&1  # Install git

  # Create Service Account and add to sudoers
  logger -s "Adding service account ($SVC)" >> $LOG 2>&1  # Log service account creation
  adduser $SVC -m -U -p dummy >> $LOG 2>&1  # Create service account with a dummy password
  echo "$SVC ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-service-acct-users  # Grant sudo privileges
  chmod 440 /etc/sudoers.d/99-service-acct-users >> $LOG 2>&1  # Set permissions for sudoers file

  # Phase 2 - Fetch the install package
  logger -s "Installing in service account ($SVC)" >> $LOG 2>&1  # Log service account setup
  cd /home/$SVC >> $LOG 2>&1  # Change to service account home directory
  logger -s "pwd=$(pwd)" >> $LOG 2>&1  # Log current directory

  # Add the service account to the docker group 
  sudo gpasswd -a $SVC docker >> $LOG 2>&1
  sudo usermod -aG docker $SVC >> $LOG 2>&1
  newgrp docker >> $LOG 2>&1
  sudo systemctl restart docker >> $LOG 2>&1

  TARGET="https://github.com/$GITHUB_USER/$GITHUB_REPO.git"  # GitHub repository URL
  logger -s "Cloning source from $TARGET" >> $LOG 2>&1  # Log repository cloning
  sudo -u $SVC git clone $TARGET >> $LOG 2>&1  # Clone repository as service account
  SECRET_KEY=$(head -c 64 /dev/urandom | base64) # Generate a random secret key

  # Phase 3 - Start CTFd using Docker Compose 
  logger -s "Starting CTFd using Docker Compose" >> $LOG 2>&1 
  cd /home/$SVC/$GITHUB_REPO >> $LOG 2>&1  # Change to repository directory  
  sudo -u $SVC docker compose -f docker-compose.yml build --build-arg SECRET_KEY='"$SECRET_KEY"'
  sudo -u $SVC docker compose up -d >> $LOG 2>&1 # Run docker-compose up in detached mode

  # Phase 4 - Customisation (TOTALY OPTIONAL)
  THEME_REPO=https://github.com/CTFd/themes.git
  logger -s "Cloning source from $THEME_REPO" >> $LOG 2>&1  # Log repository cloning
  cd /home/$SVC/$GITHUB_REPO/CTFd/themes >> $LOG 2>&1
  sudo -u $SVC git clone --recursive $THEME_REPO >> $LOG 2>&1

  # Leave a breadcrumb
  date > /.setup-completed  # Mark setup completion
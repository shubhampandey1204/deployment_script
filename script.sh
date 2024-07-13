#!/bin/bash
set -xe

##################################### Static variables ####################################

operation="$1"                                                             # Give create or destroy here
service_name="$5"                                                          # Specify service name here (frontend or backend)
database_service="mysql"                                                   # Specify database service name which is use in docker compose
frontend_branch="$2"                                                       # Specify frontend branch here
backend_branch="$2"                                                        # Specify backend branch here
username="$3"                                                              # Give username of git account
PAT="$4"                                                                   # Give personal access token here
organisation="shubhampandey1204"                                           # Give git organisation name
backend_repository="SaasTool_BE"                                           # Give backend repository name
frontend_repository="SaasTool_FE"                                          # Give frontend repository name
slack_token="slack_token"                                                  # Give slack post api token
slack_channel="C078BR7AHV5"                                                # Give slack channel ID

################################## Variables for AWS #######################################

code_deploy_application_name_backend="deployment_script_backend"        # Give codedeploy backend application name here
code_deploy_group_name_backend="deployment_script_backend"              # Give codedeploy backend deployment group name here
code_deploy_application_name_frontend="deployment_script_frontend"      # Give codedeploy frontend application name here
code_deploy_group_name_frontend="deployment_script_frontend"            # Give codedeploy frontend deployment group name here

#META-TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
#IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4 -H "X-aws-ec2-metadata-token: $META-TOKEN")
#IP="127.0.0.1"  # This three line I am commented

################################## Dynamic Variables ##############################################

repo1="https://${username}:${PAT}@github.com/${organisation}/${backend_repository}.git"
repo2="https://${username}:${PAT}@github.com/${organisation}/${frontend_repository}.git"
dir_name1=$(basename -s .git ${repo1})
dir_name2=$(basename -s .git ${repo2})
WORKING_DIRECTORY=$(pwd)

##################################### variable building acording to docker-compose version #######################

installed_compose_version=$(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

container_name_changed_version="1.29.2"
if [ "$(printf '%s\n' "$installed_compose_version" "$container_name_changed_version" | sort -V | head -n1)" = "$installed_compose_version" ];
then
        container_name="$(echo "${PWD##*/}" | tr '[:upper:]' '[:lower:]')_$(echo "$service_name")_1"
        database_container="$(echo "${PWD##*/}" | tr '[:upper:]' '[:lower:]')_$(echo "$database_service")_1"
else
        container_name="$(echo "${PWD##*/}" | tr '[:upper:]' '[:lower:]')-$(echo "$service_name")-1"
        database_container="$(echo "${PWD##*/}" | tr '[:upper:]' '[:lower:]')-$(echo "$database_service")-1"
fi

image_name_changed_version="2.8.0"
if [ "$(printf '%s\n' "$installed_compose_version" "$image_name_changed_version" | sort -V | head -n1)" = "$image_name_changed_version" ];
then
        image_name="$(echo "${PWD##*/}" | tr '[:upper:]' '[:lower:]')-$(echo "$service_name")"
else
        image_name="$(echo "${PWD##*/}" | tr '[:upper:]' '[:lower:]')_$(echo "$service_name")"
fi

########################## Function for generating messages ####################################

send_txt_message() {
    local message=$1
    curl -X POST "https://slack.com/api/chat.postMessage" -H  "accept: application/json" -d token=$slack_token -d channel=$slack_channel -d text="$message" -d as_user=true
}

send_message_with_attech_thread() {
    local message="$1"
    local file_name="$2"
    local thread_comment="$3"
    file_size=$(stat --printf="%s" $file_name)
    curl -X POST "https://slack.com/api/chat.postMessage" -H  "accept: application/json" -d token=$slack_token -d channel=$slack_channel -d text="$message" -d as_user=true > thread_stamp.json
    local thread_ts="$(cat thread_stamp.json | jq -r '.message.ts')"
    curl -s -F files=@$file_name -F filename=$file_name -F token=$slack_token -F length=$file_size https://slack.com/api/files.getUploadURLExternal > file_id.json
    upload_url=$(cat file_id.json | jq -r .upload_url)
    file_id=$(cat file_id.json | jq -r .file_id)
    curl -F  filename="@$file_name" -H "Authorization: Bearer $slack_token" -v POST $upload_url
    curl -X POST -H "Authorization: Bearer $slack_token" -H "Content-Type: application/json" -d '{"files":[{"id":"'${file_id}'","title":"'$thread_comment'"}],"channel_id":"'${slack_channel}'","thread_ts":"'$thread_ts'"}' https://slack.com/api/files.completeUploadExternal
    rm -f thread_stamp.json file_id.json
}

send_file_in_slack() {
    local file_name="$1"
    local message="$2"
    local file_size=$(stat --printf="%s" $file_name)
    curl -s -F files=@$file_name -F filename=$file_name -F token=$slack_token -F length=$file_size https://slack.com/api/files.getUploadURLExternal > file_id.json
    upload_url=$(cat file_id.json | jq -r .upload_url)
    file_id=$(cat file_id.json | jq -r .file_id)
    curl -F  filename="@$file_name" -H "Authorization: Bearer $slack_token" -v POST $upload_url
    curl -X POST -H "Authorization: Bearer $slack_token" -H "Content-Type: application/json" -d '{"files":[{"id":"'${file_id}'","title":"'$message'"}],"channel_id":"'${slack_channel}'"}' https://slack.com/api/files.completeUploadExternal
    rm -f file_id.json
}

###################################### function for cloaning the directory ################################

create_directory_and_cloning () {
cd $WORKING_DIRECTORY
if [ -d "./project-dir" ];
then
    cd $WORKING_DIRECTORY/project-dir
    if [ -d "./${dir_name1}" ];
    then
        echo "Directory backend exists"
        if [ $service_name == backend ];
        then
            cd ./${dir_name1}
            echo ${dir_name1}
            stored_url=$(git config --get remote.origin.url)
            echo "repo_url: ${repo1}"
            echo "stored_url: $stored_url"
            if [ "$(echo "${repo1}" | tr -d '[:space:]')" == "$(echo "$stored_url" | tr -d '[:space:]')" ]; then
                echo "Credentials verified..."
                git pull
            else
                echo "updating this creds......."
                git remote set-url origin ${repo1}
                echo "updated url is ${repo1}"
                echo "Updated credentials..."
                git pull
            fi
        fi
    else
        git clone ${repo1}
    fi
    cd $WORKING_DIRECTORY/project-dir
    if [ -d "./${dir_name2}" ];
    then
        echo "Directory frontend exists"
        if [ $service_name == frontend ];
        then
            cd ./${dir_name2}
            echo ${dir_name2}
            stored_url=$(git config --get remote.origin.url)
            echo "repo_url: ${repo2}"
            echo "stored_url: $stored_url"
            if [ "$(echo "${repo2}" | tr -d '[:space:]')" == "$(echo "$stored_url" | tr -d '[:space:]')" ]; then
                echo "Credentials verified..."
                git pull
            else
                echo "updating this creds......."
                git remote set-url origin ${repo2}
                echo "updated url is ${repo2}"
                echo "Updated credentials..."
                git pull
            fi
        fi
    else
        git clone ${repo2}
    fi
else
    mkdir ./project-dir && cd ./project-dir
    git clone ${repo1}
    git clone ${repo2}
fi
}
################## Function for checking branch existence ################

branch_exist() {
local branch=$1
local existed_in_repo=$(git ls-remote --heads origin ${branch})
    if [[ -z ${existed_in_repo} ]] || [[ $branch == '' ]]; then
        echo "Provided branch not found using default branch"
        git checkout master
    else
        echo "your branch is ${branch}"
        git checkout ${branch}

    fi
}

################## Function for creating database container ##########################

db_container (){
 containers=$(docker ps -f "status=running" --format "{{.Names}}")
 if  [ -z "$containers | grep -q $database_container" ] ;
 then
    echo "database container is already present no need to up container"
 else
    cd $WORKING_DIRECTORY
    sudo docker-compose up -d $database_service
 fi
}

######################## database container status ###############################

database_container_status () {
    cd $WORKING_DIRECTORY
    if [ -z $(docker-compose config --services | grep -o $database_service) ]
    then
        echo "there is no service of database"
    else
        cd $WORKING_DIRECTORY
        local db_container_name=$(docker ps -a --format '{{.Names}}' --filter "label=com.docker.compose.service=$database_service")
        if [ -z $db_container_name ]
        then
            echo "There is no container of database"
            local message="There is no container of Database. Trying to compose up of database service"
            send_txt_message "$message"
            docker-compose up -d $database_service
        else
            echo "Databse container is present now checking container is running or not"
            if [ -z $(docker ps | grep -o $db_container_name) ]
            then
                echo "container is in stopped status"
                local message="Database container is in stop state, Please check atteched logs"
                local thread_comment="Logs of stopped container"
                docker container logs --tail 200 $db_container_name &> "$(echo "$db_container_name").logs"
                local logfile="$(echo "$db_container_name").logs"
                send_message_with_attech_thread "$message" $logfile "$thread_comment"
                rm -f $logfile
                docker-compose start $database_service
            else
                echo "database container is running now check for container health status"
                sleep 35
                if [ -z $(docker ps -f health=healthy | grep -o $db_container_name) ];
                then
                    echo "container is not healthy"
                    local message="Database container is unhealthy, Please check atteched logs"
                    local thread_comment="Logs of unhealthy container"
                    docker container logs --tail 200 $db_container_name &> "$(echo "$db_container_name").logs"
                    local logfile="$(echo "$db_container_name").logs"
                    send_message_with_attech_thread "$message" $logfile "$thread_comment"
                    rm -f $logfile
                    docker-compose rm -svf $database_service
                    docker-compose up -d $database_service
                else
                    echo "Database container is in healthy state"
                    local message="Database container is in healthy state"
                    send_txt_message "$message"
                fi
            fi
        fi
    fi
}

########################### Function for checking service container and compose up #############################

create () {
    cd $WORKING_DIRECTORY
    containers=$(docker ps -f "status=running" --format "{{.Names}}")
    if [ -z "$(echo $containers | grep -o $container_name)" ];
    then
        echo "$container_name is not present"
        if [ $service_name == backend ];
        then
            cd $WORKING_DIRECTORY/project-dir/${dir_name1}
            echo "checking for branch available"
            branch_exist ${backend_branch}
            cd $WORKING_DIRECTORY
            # IMAGE=$(echo "${PWD##*/}" | tr '[:upper:]' '[:lower:]')
            # sed -i "s/server=databasedb; database=dummy; user=dummyuser; password=dummyuser@0623/Server=$ENDPOINT_ADDRESS; Port=3306; Database=dummy; User ID=root; Password=dummy@/g" /home/ec2-user/project/projectenvschema/$IMAGE/project-dir/${dir_name1}/Dockerfile
            if [ "$(sudo docker images -f "dangling=true" -q)" = "" ]; then
                database_container_status
                sudo docker-compose build --no-cache $service_name && sudo docker-compose up -d $service_name
            else
                sudo docker rmi -f $(sudo docker images -f "dangling=true" -q) || true
                database_container_status
                sudo docker-compose build --no-cache $service_name && sudo docker-compose up -d $service_name
            fi
        elif [ $service_name == frontend ];
        then
            cd $WORKING_DIRECTORY/project-dir/${dir_name2}
            echo "checking for branch available"
            branch_exist ${frontend_branch}
            cd $WORKING_DIRECTORY
            if [ "$(sudo docker images -f "dangling=true" -q)" = "" ]; then
                sudo docker-compose build --no-cache frontend && sudo docker-compose up -d frontend
            else
                sudo docker rmi -f $(sudo docker images -f "dangling=true" -q) || true
                sudo docker-compose build --no-cache frontend && sudo docker-compose up -d frontend
            fi
        fi
        echo "checking for dangling image"
        if [ "$(sudo docker images -f "dangling=true" -q)" = "" ]; then
            echo "no dangling image created"
        else
            echo "dangling image created know removing dangling images"
            sudo docker rmi -f $(sudo docker images -f "dangling=true" -q) || true
        fi
        echo "cleaning build cache"
        docker builder prune -f
    else
        echo "$container_name is up"
    fi
}

################################ Function for checking container and image status and removing it ##################

remove_container_and_images () {

    cd $WORKING_DIRECTORY
    echo "removing container from system"
    if [ -z $(docker ps -a | grep -o $container_name) ];
    then
        echo "no running container of service $service_name"
    else
        echo "container is present"
        sudo docker-compose rm -svf $service_name
    fi

    echo "Removing images from local system"
    image_status=$(docker images --format "{{.Repository}}:{{.Tag}}")
    if [ "$(echo "$image_status" | grep $image_name | grep latest)" = "" ];
    then
        echo "Image not found locally skipping it"
    else
        echo "Removing image $image_name"
        sudo docker rmi -f $image_name:latest
    fi

    echo "check for dangling images"
    if [ "$(sudo docker images -f "dangling=true" -q)" = "" ]; then
      echo "no dangling image created"
    else
      echo "dangling image created know removing dangling images"
      sudo docker rmi -f $(sudo docker images -f "dangling=true" -q) || true
    fi

    echo "check for failed tag imagaes"
    if [ "$(docker image ls | grep failed)" == "" ];
    then
        echo "No failed image found"
    else
        echo "removing failed image"
        docker rmi -f $(docker image ls | grep failed | awk '{print $3}')
    fi

    echo "cleaning build cache"
    docker builder prune -f
}

################################ Function for checking new commit on repository and removing container and image ##################

destroy () {
  cd $WORKING_DIRECTORY
  if [ -d "./project-dir" ];
  then
    cd $WORKING_DIRECTORY/project-dir
    if [ $service_name == backend ];
    then
      if [ -d "./${dir_name1}" ];
      then
        cd ./${dir_name1}
        git remote update
        status=$(git status -uno | awk 'FNR == 2 {print $4}')
        if [ "$status" == "up" ]; then
          echo "your backend repo is upto date"
          cd $WORKING_DIRECTORY
        else
          echo "docker compose is destroying"
          remove_container_and_images
        fi
      else
        create_directory_and_cloning
        remove_container_and_images
      fi
    elif [ $service_name == frontend ];
    then
      if [ -d "./${dir_name2}" ];
      then
        cd ./${dir_name2}
        git remote update
        status=$(git status -uno | awk 'FNR == 2 {print $4}')
        if [ "$status" == "up" ]; then
          echo "your frontend repo is upto date"
          cd $WORKING_DIRECTORY
        else
          echo "docker compose is destroying"
          remove_container_and_images
        fi
      else
        create_directory_and_cloning
        remove_container_and_images
      fi
    fi
  else
    echo "project-dir is not present"
    create_directory_and_cloning
    remove_container_and_images
  fi
}

############################### Function for creating backup of running container ##############################

creating_backup () {
sleep 10
cd $WORKING_DIRECTORY
for services in $service_name
do
    containers=$(docker ps -f "status=running" --format "{{.Names}}")
    if [ -z "$(echo $containers | grep -o $container_name)" ];
        then
        echo "No running container found for service '$services'." > /dev/null 2>&1
    else
      echo "Container name for service '$services' is: $container_name" > /dev/null 2>&1
      image_status=$(docker images --filter reference=$image_name:backup | grep $image_name | awk '{print $2}')
      if  [ "$image_status" == "backup" ]; then
        echo "backup image is already avilable"
        docker rmi -f $image_name:backup
        docker commit $container_name $image_name:backup
      else
        docker commit $container_name $image_name:backup
      fi
    fi
done
}

######################### Function for performing rollback in down containers #######################

rollback_container() {
    cd $WORKING_DIRECTORY
    image_status=$(docker images --filter reference=$image_name:backup | grep $image_name | awk '{print $2}')
    if  [ "$image_status" == "backup" ]; then
        docker tag "${image_name}:latest" "${image_name}:failed"
        docker tag "${image_name}:backup" "${image_name}:latest"
        docker-compose up -d $service_name
    else
        docker-compose up -d $service_name
    fi
}

############################## Function for sending aws pipeline logs ##########################################

aws_pipeline_logs () {
  local code_deploy_application_name=$1
  local code_deploy_group_name=$2
  deploymant_group_id=$(aws deploy get-deployment-group --application-name $code_deploy_application_name --deployment-group-name $code_deploy_group_name --query deploymentGroupInfo.deploymentGroupId | tr -d '"')
  cd /opt/codedeploy-agent/deployment-root/$deploymant_group_id/
  latest_directory=$(ls -c1 | head -n1)
  cd $latest_directory/logs
  cp scripts.log $WORKING_DIRECTORY
  cd $WORKING_DIRECTORY
  file=scripts.log
  message="deployment_script_log_file"
  send_file_in_slack $file $message
  rm -r $WORKING_DIRECTORY/scripts.log
}

############################## Function for checking containers status and sending message ###################################

check_container_status () {
    cd $WORKING_DIRECTORY
    local container_status=$(docker ps -f "status=running" --format "{{.Names}}")
    if [ -z $(echo $container_status | grep -o $container_name) ];
    then
        local message="Container $container_name is down. Performing Roll back, please check atteched logfile"
        docker container logs --tail 30 $container_name &> "$(echo "$container_name").logs"
        local logfile="$(echo "$container_name").logs"
        local thread_comment="last_30_logs_of_down_container"
        send_message_with_attech_thread "$message" $logfile "$thread_comment"
        rm -f $logfile
        rollback_container
        ########### checking rollback result #################
        sleep 10
        local container_status=$(docker ps -f "status=running" --format "{{.Names}}")

        if [ -z $(echo "$container_status" | grep -o $container_name) ];
        then
            local message="$container_name is still down needs to check code and configuration"
            send_txt_message "$message"
        else
            local message="Rollback successfull $container_name is up"
            send_txt_message "$message"
        fi

        if [ $service_name == backend ]
        then
            aws_pipeline_logs $code_deploy_application_name_backend $code_deploy_group_name_backend
        else
            aws_pipeline_logs $code_deploy_application_name_frontend $code_deploy_group_name_frontend
        fi

    else
        message="Container $container_name is up"
        send_txt_message "$message"
    fi
}

case ${operation} in
  create) create_directory_and_cloning && create && creating_backup && check_container_status ;;
    destroy) destroy ;;
            *) echo "Unknown action ${operation}" ;;
esac

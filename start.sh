#!/bin/bash

set -eo pipefail

email_prompt() {
    read -p "Please provide us with your email address: " EMAIL
    while true; do
        if [ -z "$EMAIL" ]; then
            break
        fi
        read -p "Is this email correct? $EMAIL - [y/n]: " yn
        case $yn in
        [Yy]*) break ;;
        [Nn]*)
            email_prompt
            exit 1
            ;;
        esac
    done
    printf "Thank you! 🙏\n"
}

function parseFlags() {
    while (($#)); do
        case "$1" in
        --run-cli)
            run_cli=1
            shift 1
            ;;
        --email)
            email_override=$2
            shift 2
            ;;
        --source)
            source=$2
            shift 2
            ;;
        *)
            echo "Unrecognized arg: $1"
            shift
            ;;
        esac
    done
}

main() {
    RUNNING=$(docker compose ps -q --status=running | wc -l)
    if [ "$RUNNING" -gt 0 ]; then
        printf "Faros CE is still running. \n"
        printf "You can stop it with the ./stop.sh command. \n"
        exit 1
    fi

    parseFlags "$@"
    EMAIL_FILE=".faros-email"
    if [[ -n "$email_override" ]]; then
        EMAIL=$email_override
        echo "$email_override" >$EMAIL_FILE
    else
        if [[ -f "$EMAIL_FILE" ]]; then
            EMAIL=$(cat $EMAIL_FILE)
        else
            printf "Hello 👋 Welcome to Faros Community Edition! 🤗\n\n"
            printf "Want to stay up to date with the latest community news? (we won't spam you)\n"
            email_prompt
            echo "$EMAIL" >$EMAIL_FILE
        fi
    fi

    export FAROS_EMAIL=$EMAIL

    if [[ -n "$source" ]]; then
        SOURCE=$source
    else
        SOURCE="unknown"
    fi
    export FAROS_START_SOURCE=$SOURCE

    # Ensure we're using the latest faros-init image
    export FAROS_INIT_IMAGE=farosai.docker.scarf.sh/farosai/faros-ce-init:latest
    docker compose pull faros-init
    # docker image ls appears to be sorted by creation date
    VERSION=$(docker image ls -q $FAROS_INIT_IMAGE | head -n 1)
    export FAROS_INIT_VERSION=$VERSION

    if [[ $(uname -m 2>/dev/null) == 'arm64' ]]; then
        # Use Metabase images built for Apple M1
        METABASE_IMAGE="farosai.docker.scarf.sh/farosai/metabase-m1" \
        docker compose up --build --remove-orphans --detach && docker compose logs --follow faros-init
    else
        docker compose up --build --remove-orphans --detach && docker compose logs --follow faros-init
    fi

    if ((run_cli)); then
        CONTAINER_EXIT_CODE=$(docker wait faros-community-edition-faros-init-1)
        if [ "$CONTAINER_EXIT_CODE" -gt 0 ]; then
            printf "An error occured during the initialization of Faros CE.\n"
            printf "For troubleshooting help, you can bring this log on our Slack workspace:\n"
            printf "https://community.faros.ai/docs/slack \n"
            exit 1
        fi
        ./run_cli.sh
    fi
}

main "$@"
exit

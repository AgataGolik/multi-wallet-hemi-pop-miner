#!/bin/bash

# ... (pozostała część skryptu pozostaje bez zmian)

# Dodaj tę funkcję na końcu skryptu, przed główną pętlą:

view_logs() {
    local wallet_number=$1
    local log_file="$LOG_DIR/hemi_wallet_$wallet_number.log"
    
    if [ -f "$log_file" ]; then
        tail -f "$log_file"
    else
        show "Log file for wallet $wallet_number not found."
    fi
}

# Zmodyfikuj główną pętlę, aby dodać opcję przeglądania logów:

wallet_count=0
while true; do
    echo
    show "1. Create a new wallet and start mining"
    show "2. View logs for an existing wallet"
    show "3. Exit"
    read -p "Choose an option (1/2/3): " choice
    
    case $choice in
        1)
            wallet_count=$((wallet_count + 1))
            show "Creating wallet $wallet_count"
            if generate_wallet $wallet_count; then
                create_and_start_service $wallet_count
            else
                wallet_count=$((wallet_count - 1))
            fi
            ;;
        2)
            read -p "Enter wallet number to view logs: " log_wallet
            view_logs $log_wallet
            ;;
        3)
            break
            ;;
        *)
            show "Invalid option. Please try again."
            ;;
    esac
done

show "PoP mining successfully started for $wallet_count wallet(s)"
show "You can check the logs for each wallet in the $LOG_DIR directory"

#!/bin/bash

# Linux User Management System
# This script provides a user-friendly interface for managing Linux users
# using dialog widgets for better user experience.

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "Error: dialog is not installed. Please install it using:"
    echo "sudo apt-get install dialog (Debian/Ubuntu)"
    echo "sudo yum install dialog (CentOS/RHEL)"
    exit 1
fi

# Check if running with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script requires root privileges."
    echo "Please run with sudo or as root."
    exit 1
fi

# Initialize variables
DIALOG_CANCEL=1
DIALOG_ESC=255
HEIGHT=20
WIDTH=70
CHOICE_HEIGHT=10

# Function to display error messages
show_error() {
    dialog --title "Error" --msgbox "$1" 8 40
}

# Function to validate username
validate_username() {
    local username="$1"
    
    # Check if username is empty
    if [ -z "$username" ]; then
        show_error "Username cannot be empty."
        return 1
    fi
    
    # Check if username follows valid format (only alphanumeric and underscore, starting with letter)
    if ! [[ "$username" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        show_error "Invalid username format. Username must start with a letter and contain only letters, numbers, underscores, or hyphens."
        return 1
    fi
    
    return 0
}

# Function to validate group name
validate_groupname() {
    local groupname="$1"
    
    # Check if groupname is empty
    if [ -z "$groupname" ]; then
        show_error "Group name cannot be empty."
        return 1
    fi
    
    # Check if groupname follows valid format
    if ! [[ "$groupname" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        show_error "Invalid group name format. Group name must start with a letter and contain only letters, numbers, underscores, or hyphens."
        return 1
    fi
    
    return 0
}

# Function to add a new user
add_user() {
    # Get username
    username=$(dialog --title "Add User" --inputbox "Enter username:" 8 40 3>&1 1>&2 2>&3)
    
    # Check if user canceled
    if [ $? -ne 0 ]; then
        return
    fi
    
    # Validate username
    validate_username "$username" || return

    # Check if user already exists
    if id "$username" &>/dev/null; then
        show_error "User '$username' already exists."
        return
    fi
    
    # Get full name
    fullname=$(dialog --title "Add User" --inputbox "Enter full name:" 8 40 3>&1 1>&2 2>&3)
    
    # Check if user canceled
    if [ $? -ne 0 ]; then
        return
    fi
    
    # Ask if user should be an administrator
    dialog --title "Add User" --yesno "Should this user be an administrator (sudo)?" 8 40
    admin=$?
    
    # Ask if user should have home directory
    dialog --title "Add User" --yesno "Create home directory for this user?" 8 40
    create_home=$?
    
    # Set home directory option
    if [ $create_home -eq 0 ]; then
        home_opt="-m"
    else
        home_opt=""
    fi
    
    # Create user with specified options
    if ! useradd $home_opt -c "$fullname" "$username"; then
        show_error "Failed to create user."
        return
    fi
    
    # Set password for new user
    password=$(dialog --title "Add User" --passwordbox "Enter password for $username:" 8 40 3>&1 1>&2 2>&3)
    
    # Check if user canceled
    if [ $? -ne 0 ]; then
        # Delete user if user canceled password entry
        userdel -r "$username" &>/dev/null
        show_error "User creation canceled. User has been removed."
        return
    fi
    
    # Check password strength
    if [ ${#password} -lt 8 ]; then
        dialog --title "Password Warning" --yesno "Password is less than 8 characters. Use anyway?" 8 40
        if [ $? -ne 0 ]; then
            # Delete user if password is rejected
            userdel -r "$username" &>/dev/null
            show_error "User creation canceled. User has been removed."
            return
        fi
    fi
    
    # Set the password
    echo "$username:$password" | chpasswd
    if [ $? -ne 0 ]; then
        userdel -r "$username" &>/dev/null
        show_error "Failed to set password. User has been removed."
        return
    fi
    
    # Add to sudo group if selected
    if [ $admin -eq 0 ]; then
        if command -v usermod &> /dev/null; then
            usermod -aG sudo "$username" || usermod -aG wheel "$username"
        else
            show_error "Could not add user to admin group. Command 'usermod' not found."
        fi
    fi
    
    dialog --title "Success" --msgbox "User '$username' has been created successfully." 8 40
}

# Function to modify existing user
modify_user() {
    # Get list of users
    users=$(cut -d: -f1 /etc/passwd | sort)
    
    # Create options for dialog
    options=()
    for user in $users; do
        options+=("$user" "")
    done
    
    # Display user selection dialog
    username=$(dialog --title "Modify User" --menu "Select user to modify:" $HEIGHT $WIDTH $CHOICE_HEIGHT "${options[@]}" 3>&1 1>&2 2>&3)
    
    # Check if user canceled
    if [ $? -ne 0 ]; then
        return
    fi
    
    # Display modification options
    while true; do
        # Get user info for display
        user_id=$(id -u "$username")
        group_id=$(id -g "$username")
        groups=$(groups "$username" | cut -d: -f2)
        home_dir=$(grep "^$username:" /etc/passwd | cut -d: -f6)
        shell=$(grep "^$username:" /etc/passwd | cut -d: -f7)
        
        option=$(dialog --title "Modify User: $username" --menu "Choose action:" $HEIGHT $WIDTH $CHOICE_HEIGHT \
            "1" "Change password" \
            "2" "Change user's full name" \
            "3" "Add to group" \
            "4" "Remove from group" \
            "5" "Change login shell" \
            "6" "Lock/unlock account" \
            "7" "Show user information" \
            "8" "Return to main menu" \
            3>&1 1>&2 2>&3)
        
        # Check if user canceled
        if [ $? -ne 0 ] || [ "$option" = "8" ]; then
            break
        fi
        
        case $option in
            1) # Change password
                password=$(dialog --title "Change Password" --passwordbox "Enter new password for $username:" 8 40 3>&1 1>&2 2>&3)
                if [ $? -eq 0 ]; then
                    # Check password strength
                    if [ ${#password} -lt 8 ]; then
                        dialog --title "Password Warning" --yesno "Password is less than 8 characters. Use anyway?" 8 40
                        if [ $? -ne 0 ]; then
                            continue
                        fi
                    fi
                    
                    echo "$username:$password" | chpasswd
                    if [ $? -eq 0 ]; then
                        dialog --title "Success" --msgbox "Password for '$username' has been updated." 8 40
                    else
                        show_error "Failed to change password."
                    fi
                fi
                ;;
                
            2) # Change full name (comment)
                current_fullname=$(grep "^$username:" /etc/passwd | cut -d: -f5 | cut -d, -f1)
                fullname=$(dialog --title "Change Full Name" --inputbox "Enter new full name for $username:" 8 40 "$current_fullname" 3>&1 1>&2 2>&3)
                if [ $? -eq 0 ]; then
                    usermod -c "$fullname" "$username"
                    if [ $? -eq 0 ]; then
                        dialog --title "Success" --msgbox "Full name for '$username' has been updated." 8 40
                    else
                        show_error "Failed to change full name."
                    fi
                fi
                ;;
                
            3) # Add to group
                # Get list of groups
                groups=$(cut -d: -f1 /etc/group | sort)
                
                # Create options for dialog
                group_options=()
                for group in $groups; do
                    group_options+=("$group" "")
                done
                
                groupname=$(dialog --title "Add to Group" --menu "Select group:" $HEIGHT $WIDTH $CHOICE_HEIGHT "${group_options[@]}" 3>&1 1>&2 2>&3)
                
                if [ $? -eq 0 ]; then
                    usermod -aG "$groupname" "$username"
                    if [ $? -eq 0 ]; then
                        dialog --title "Success" --msgbox "User '$username' has been added to group '$groupname'." 8 40
                    else
                        show_error "Failed to add user to group."
                    fi
                fi
                ;;
                
            4) # Remove from group
                # Get list of groups the user belongs to
                user_groups=$(groups "$username" | cut -d: -f2 | sed 's/^[ \t]*//' | tr ' ' '\n' | sort)
                
                # Create options for dialog
                group_options=()
                for group in $user_groups; do
                    # Skip primary group
                    if [ "$group" != "$(id -gn "$username")" ]; then
                        group_options+=("$group" "")
                    fi
                done
                
                if [ ${#group_options[@]} -eq 0 ]; then
                    show_error "User is not a member of any secondary groups."
                    continue
                fi
                
                groupname=$(dialog --title "Remove from Group" --menu "Select group:" $HEIGHT $WIDTH $CHOICE_HEIGHT "${group_options[@]}" 3>&1 1>&2 2>&3)
                
                if [ $? -eq 0 ]; then
                    gpasswd -d "$username" "$groupname"
                    if [ $? -eq 0 ]; then
                        dialog --title "Success" --msgbox "User '$username' has been removed from group '$groupname'." 8 40
                    else
                        show_error "Failed to remove user from group."
                    fi
                fi
                ;;
                
            5) # Change login shell
                # Get list of available shells
                shells=$(cat /etc/shells | grep -v "^#")
                
                # Create options for dialog
                shell_options=()
                for shell_option in $shells; do
                    shell_options+=("$shell_option" "")
                done
                
                new_shell=$(dialog --title "Change Shell" --menu "Select login shell:" $HEIGHT $WIDTH $CHOICE_HEIGHT "${shell_options[@]}" 3>&1 1>&2 2>&3)
                
                if [ $? -eq 0 ]; then
                    usermod -s "$new_shell" "$username"
                    if [ $? -eq 0 ]; then
                        dialog --title "Success" --msgbox "Login shell for '$username' has been updated to '$new_shell'." 8 40
                    else
                        show_error "Failed to change shell."
                    fi
                fi
                ;;
                
            6) # Lock/unlock account
                # Check if account is locked
                passwd_status=$(passwd -S "$username" | awk '{print $2}')
                
                if [ "$passwd_status" = "L" ] || [ "$passwd_status" = "LK" ]; then
                    # Account is locked, ask to unlock
                    dialog --title "Account Status" --yesno "Account for '$username' is locked. Unlock it?" 8 40
                    if [ $? -eq 0 ]; then
                        usermod -U "$username"
                        if [ $? -eq 0 ]; then
                            dialog --title "Success" --msgbox "Account for '$username' has been unlocked." 8 40
                        else
                            show_error "Failed to unlock account."
                        fi
                    fi
                else
                    # Account is unlocked, ask to lock
                    dialog --title "Account Status" --yesno "Account for '$username' is unlocked. Lock it?" 8 40
                    if [ $? -eq 0 ]; then
                        usermod -L "$username"
                        if [ $? -eq 0 ]; then
                            dialog --title "Success" --msgbox "Account for '$username' has been locked." 8 40
                        else
                            show_error "Failed to lock account."
                        fi
                    fi
                fi
                ;;
                
            7) # Show user information
                # Get detailed user information
                user_id=$(id -u "$username")
                group_id=$(id -g "$username")
                primary_group=$(id -gn "$username")
                secondary_groups=$(id -Gn "$username" | sed "s/$primary_group //")
                home_dir=$(grep "^$username:" /etc/passwd | cut -d: -f6)
                shell=$(grep "^$username:" /etc/passwd | cut -d: -f7)
                comment=$(grep "^$username:" /etc/passwd | cut -d: -f5)
                
                account_status=$(passwd -S "$username" | awk '{print $2}')
                if [ "$account_status" = "L" ] || [ "$account_status" = "LK" ]; then
                    account_status="Locked"
                else
                    account_status="Active"
                fi
                
                last_password_change=$(passwd -S "$username" | awk '{print $3}')
                
                # Check if user is in sudo group
                if groups "$username" | grep -q "\bsudo\b" || groups "$username" | grep -q "\bwheel\b"; then
                    admin_status="Yes"
                else
                    admin_status="No"
                fi
                
                # Show information in a message box
                dialog --title "User Information: $username" --msgbox "\
Username: $username
User ID: $user_id
Full Name: $comment
Primary Group: $primary_group ($group_id)
Secondary Groups: $secondary_groups
Home Directory: $home_dir
Shell: $shell
Account Status: $account_status
Last Password Change: $last_password_change
Administrator: $admin_status" \
                $HEIGHT $WIDTH
                ;;
        esac
    done
}

# Function to delete user
delete_user() {
    # Get list of users, excluding system users
    users=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd | sort)
    
    # Create options for dialog
    options=()
    for user in $users; do
        # Get full name for description
        fullname=$(grep "^$user:" /etc/passwd | cut -d: -f5 | cut -d, -f1)
        options+=("$user" "$fullname")
    done
    
    # Display user selection dialog
    username=$(dialog --title "Delete User" --menu "Select user to delete:" $HEIGHT $WIDTH $CHOICE_HEIGHT "${options[@]}" 3>&1 1>&2 2>&3)
    
    # Check if user canceled
    if [ $? -ne 0 ]; then
        return
    fi
    
    # Check if trying to delete current user
    if [ "$username" = "$(whoami)" ]; then
        show_error "Cannot delete the currently logged-in user."
        return
    fi
    
    # Confirm deletion
    dialog --title "Delete User" --yesno "Are you sure you want to delete user '$username'?" 8 40
    if [ $? -ne 0 ]; then
        return
    fi
    
    # Ask if home directory should be deleted
    dialog --title "Delete User" --yesno "Delete home directory and mail spool of '$username' as well?" 8 40
    remove_home=$?
    
    # Set deletion options
    if [ $remove_home -eq 0 ]; then
        delete_opt="-r"
    else
        delete_opt=""
    fi
    
    # Delete user
    if userdel $delete_opt "$username"; then
        dialog --title "Success" --msgbox "User '$username' has been deleted successfully." 8 40
    else
        show_error "Failed to delete user. The user might be currently logged in or running processes."
    fi
}

# Function to manage groups
manage_groups() {
    while true; do
        option=$(dialog --title "Group Management" --menu "Choose action:" $HEIGHT $WIDTH $CHOICE_HEIGHT \
            "1" "Create new group" \
            "2" "Delete group" \
            "3" "List groups" \
            "4" "Show group members" \
            "5" "Return to main menu" \
            3>&1 1>&2 2>&3)
        
        # Check if user canceled
        if [ $? -ne 0 ] || [ "$option" = "5" ]; then
            break
        fi
        
        case $option in
            1) # Create new group
                groupname=$(dialog --title "Create Group" --inputbox "Enter group name:" 8 40 3>&1 1>&2 2>&3)
                
                # Check if user canceled
                if [ $? -ne 0 ]; then
                    continue
                fi
                
                # Validate group name
                validate_groupname "$groupname" || continue
                
                # Check if group already exists
                if getent group "$groupname" &>/dev/null; then
                    show_error "Group '$groupname' already exists."
                    continue
                fi
                
                # Create group
                if groupadd "$groupname"; then
                    dialog --title "Success" --msgbox "Group '$groupname' has been created successfully." 8 40
                else
                    show_error "Failed to create group."
                fi
                ;;
                
            2) # Delete group
                # Get list of groups, excluding system groups
                groups=$(awk -F: '$3 >= 1000 {print $1}' /etc/group | sort)
                
                # Create options for dialog
                group_options=()
                for group in $groups; do
                    group_options+=("$group" "")
                done
                
                if [ ${#group_options[@]} -eq 0 ]; then
                    show_error "No non-system groups found."
                    continue
                fi
                
                groupname=$(dialog --title "Delete Group" --menu "Select group to delete:" $HEIGHT $WIDTH $CHOICE_HEIGHT "${group_options[@]}" 3>&1 1>&2 2>&3)
                
                # Check if user canceled
                if [ $? -ne 0 ]; then
                    continue
                fi
                
                # Confirm deletion
                dialog --title "Delete Group" --yesno "Are you sure you want to delete group '$groupname'?" 8 40
                if [ $? -ne 0 ]; then
                    continue
                fi
                
                # Delete group
                if groupdel "$groupname"; then
                    dialog --title "Success" --msgbox "Group '$groupname' has been deleted successfully." 8 40
                else
                    show_error "Failed to delete group. The group might be a primary group for some users."
                fi
                ;;
                
            3) # List groups
                # Get all groups with their GIDs
                group_list=$(awk -F: '{print $1 " (GID: " $3 ")"}' /etc/group | sort)
                
                # Display groups in a scroll box
                dialog --title "Group List" --msgbox "$group_list" $HEIGHT $WIDTH
                ;;
                
            4) # Show group members
                # Get list of groups
                groups=$(cut -d: -f1 /etc/group | sort)
                
                # Create options for dialog
                group_options=()
                for group in $groups; do
                    group_options+=("$group" "")
                done
                
                groupname=$(dialog --title "Group Members" --menu "Select group:" $HEIGHT $WIDTH $CHOICE_HEIGHT "${group_options[@]}" 3>&1 1>&2 2>&3)
                
                # Check if user canceled
                if [ $? -ne 0 ]; then
                    continue
                fi
                
                # Get group members
                group_info=$(getent group "$groupname")
                group_id=$(echo "$group_info" | cut -d: -f3)
                explicit_members=$(echo "$group_info" | cut -d: -f4 | tr ',' ' ')
                
                # Get users who have this as their primary group
                primary_members=$(awk -F: "\$4 == $group_id {print \$1}" /etc/passwd)
                
                # Combine member lists
                all_members="$explicit_members $primary_members"
                
                # Remove duplicates
                all_members=$(echo "$all_members" | tr ' ' '\n' | sort -u | tr '\n' ' ')
                
                if [ -z "$all_members" ]; then
                    message="Group '$groupname' (GID: $group_id) has no members."
                else
                    message="Group '$groupname' (GID: $group_id) members:\n\n$all_members"
                fi
                
                # Display group members
                dialog --title "Group Members" --msgbox "$message" $HEIGHT $WIDTH
                ;;
        esac
    done
}

# Function to list users
list_users() {
    # Ask what kind of users to list
    option=$(dialog --title "List Users" --menu "Choose users to list:" $HEIGHT $WIDTH $CHOICE_HEIGHT \
        "1" "All users" \
        "2" "Regular users (UID >= 1000)" \
        "3" "System users (UID < 1000)" \
        "4" "Return to main menu" \
        3>&1 1>&2 2>&3)
    
    # Check if user canceled
    if [ $? -ne 0 ] || [ "$option" = "4" ]; then
        return
    fi
    
    # Prepare user list based on option
    case $option in
        1) # All users
            user_list=$(awk -F: '{print $1 " (UID: " $3 ", GID: " $4 ")"}' /etc/passwd | sort)
            title="All Users"
            ;;
        2) # Regular users
            user_list=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1 " (UID: " $3 ", GID: " $4 ")"}' /etc/passwd | sort)
            title="Regular Users"
            ;;
        3) # System users
            user_list=$(awk -F: '$3 < 1000 || $3 == 65534 {print $1 " (UID: " $3 ", GID: " $4 ")"}' /etc/passwd | sort)
            title="System Users"
            ;;
    esac
    
    # Display users in a scroll box
    dialog --title "$title" --msgbox "$user_list" $HEIGHT $WIDTH
}

# Function to check system stats
system_stats() {
    # Get system stats
    hostname=$(hostname)
    os_info=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d= -f2 | tr -d '"')
    if [ -z "$os_info" ]; then
        os_info=$(uname -s)
    fi
    kernel=$(uname -r)
    uptime=$(uptime -p)
    total_users=$(cat /etc/passwd | wc -l)
    regular_users=$(awk -F: '$3 >= 1000 && $3 != 65534' /etc/passwd | wc -l)
    system_users=$(( total_users - regular_users ))
    total_groups=$(cat /etc/group | wc -l)
    
    # Get disk usage
    disk_usage=$(df -h / | tail -n 1 | awk '{print $5 " used (" $3 " of " $2 ")"}')
    
    # Get memory usage
    if command -v free &> /dev/null; then
        memory_usage=$(free -h | grep Mem | awk '{print $3 " used of " $2 " total (" int($3/$2*100) "%)"}')
    else
        memory_usage="Not available"
    fi
    
    # Display system stats
    dialog --title "System Statistics" --msgbox "\
Hostname: $hostname
OS: $os_info
Kernel: $kernel
Uptime: $uptime
Users: $total_users total ($regular_users regular, $system_users system)
Groups: $total_groups
Disk Usage: $disk_usage
Memory Usage: $memory_usage" \
    $HEIGHT $WIDTH
}

# Function to show help
show_help() {
    dialog --title "Help" --msgbox "\
Linux User Management System

This application provides a user-friendly interface for managing Linux users and groups.

Main Functions:
- Add User: Create a new user account with various options
- Modify User: Change user settings, group membership, etc.
- Delete User: Remove a user account and optionally its home directory
- Manage Groups: Create/delete groups and view membership
- List Users: View different categories of system users
- System Stats: View basic system information

Note: Most operations require root privileges.

For more detailed help on Linux user management, consult:
man useradd
man usermod
man userdel
man groupadd
man groupdel

Press OK to return to the main menu." \
    $HEIGHT $WIDTH
}

# Main menu loop
while true; do
    # Display main menu
    option=$(dialog --clear --title "Linux User Management System" --menu "Choose an option:" $HEIGHT $WIDTH $CHOICE_HEIGHT \
        "1" "Add User" \
        "2" "Modify User" \
        "3" "Delete User" \
        "4" "Manage Groups" \
        "5" "List Users" \
        "6" "System Statistics" \
        "7" "Help" \
        "8" "Exit" \
        3>&1 1>&2 2>&3)
    
    # Check if user pressed Cancel or ESC
    if [ $? -eq $DIALOG_CANCEL ] || [ $? -eq $DIALOG_ESC ] || [ "$option" = "8" ]; then
        clear
        echo "Thank you for using Linux User Management System."
        exit 0
    fi
    
    # Process user choice
    case $option in
        1) add_user ;;
        2) modify_user ;;
        3) delete_user ;;
        4) manage_groups ;;
        5) list_users ;;
        6) system_stats ;;
        7) show_help ;;
    esac
done

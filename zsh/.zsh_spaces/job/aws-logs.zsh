# AWS Logs Configuration
# Available log streams
AWS_LOG_STREAMS=(
    "/aws/lambda/dev-rescue-serverless-monitoring-data-extractor"
    "/aws/lambda/dev-rescue-serverless-monitoring-data-processor"
    "/aws/lambda/dev-rescue-serverless-monitoring-notification-processor"
    "/aws/apprunner/dev-rescue-serverless-mqtt-worker/6ce023ee88034697b34d2452f9b98a2a/application"
    "/aws/lambda/dev-rescue-serverless-fast-api"
)

# Default time range
AWS_LOG_SINCE="10m"

# AWS logs function with fzf preview
bb_aws_logs_short() {
    # Show all available log streams
    echo "Available AWS log streams:"
    printf '%s\n' "${AWS_LOG_STREAMS[@]}" | nl
    echo ""
    
    # Interactive selection of log stream
    local log_stream=$(printf '%s\n' "${AWS_LOG_STREAMS[@]}" | fzf --prompt="Select log stream: " --height=50% --layout=reverse --border)
    if [ -z "$log_stream" ]; then
        echo "No log stream selected"
        return 1
    fi
    
    # Ask for time range
    echo "Selected log stream: $log_stream"
    echo "Current default time: $AWS_LOG_SINCE"
    echo "Enter time range (e.g., 10m, 1h, 2d, 1w) or press Enter for default:"
    read -r since_input
    
    # Use input or default
    local since="${since_input:-$AWS_LOG_SINCE}"
    
    # Parse time format (m, h, d, w)
    case "$since" in
        *m) since="${since%m}m" ;;
        *h) since="${since%h}h" ;;
        *d) since="${since%d}d" ;;
        *w) since="${since%w}w" ;;
        *) since="${since}m" ;;  # Default to minutes if no suffix
    esac
    
    echo "Fetching logs from: $log_stream (since: $since)"
    local cmd_tail="aws logs tail '$log_stream' --since '$since' | pv -l | awk '{\$1=\$2=\"\"; print substr(\$0, 3)}' > /tmp/aws_logs.txt"
    bb_confirm "$cmd_tail" || return $?
    fzf --preview 'tail -n +$(( {n} - 10 )) /tmp/aws_logs.txt | head -20 | awk "{gsub(/{}/, "\033[31;1m{}\033[0m"); print}"' \
        --preview-window=right:60%:wrap \
        --bind 'ctrl-e:execute(NVIM_APPNAME=LazyVIM nvim /tmp/aws_logs.txt +{n})' \
        < /tmp/aws_logs.txt
}

# Quick function for aliases (asks for time but uses specific log stream)
bb_aws_logs_quick() {
    local log_stream="$1"
    
    if [ -z "$log_stream" ]; then
        echo "Error: No log stream provided"
        return 1
    fi
    
    # Ask for time range
    echo "Selected log stream: $log_stream"
    echo "Current default time: $AWS_LOG_SINCE"
    echo "Enter time range (e.g., 10m, 1h, 2d, 1w) or press Enter for default:"
    read -r since_input
    
    # Use input or default
    local since="${since_input:-$AWS_LOG_SINCE}"
    
    # Parse time format (m, h, d, w)
    case "$since" in
        *m) since="${since%m}m" ;;
        *h) since="${since%h}h" ;;
        *d) since="${since%d}d" ;;
        *w) since="${since%w}w" ;;
        *) since="${since}m" ;;  # Default to minutes if no suffix
    esac
    
    echo "Fetching logs from: $log_stream (since: $since)"
    local cmd_tail="aws logs tail '$log_stream' --since '$since' | pv -l | awk '{\$1=\$2=\"\"; print substr(\$0, 3)}' > /tmp/aws_logs.txt"
    bb_confirm "$cmd_tail" || return $?
    fzf --preview 'tail -n +$(( {n} - 10 )) /tmp/aws_logs.txt | head -20 | awk "{gsub(/{}/, "\033[31;1m{}\033[0m"); print}"' \
        --preview-window=right:60%:wrap \
        --bind 'ctrl-e:execute(NVIM_APPNAME=LazyVIM nvim /tmp/aws_logs.txt +{n})' \
        < /tmp/aws_logs.txt
}

# Quick aliases for common log streams (these will also ask for time)
alias bb_aws_fast_api="bb_aws_logs_quick /aws/lambda/dev-rescue-serverless-fast-api"
alias bb_aws_extractor="bb_aws_logs_quick /aws/lambda/dev-rescue-serverless-monitoring-data-extractor"
alias bb_aws_processor="bb_aws_logs_quick /aws/lambda/dev-rescue-serverless-monitoring-data-processor"
alias bb_aws_notify="bb_aws_logs_quick /aws/lambda/dev-rescue-serverless-monitoring-notification-processor"
alias bb_aws_mqtt="bb_aws_logs_quick /aws/apprunner/dev-rescue-serverless-mqtt-worker/6ce023ee88034697b34d2452f9b98a2a/application"

# Function to add new log stream
bb_aws_add_stream() {
    if [ -z "$1" ]; then
        echo "Usage: aws-add-stream <log-stream-path>"
        echo "Example: aws-add-stream /aws/lambda/new-service"
        return 1
    fi
    
    local new_stream="$1"
    
    # Check if stream already exists
    if [[ " ${AWS_LOG_STREAMS[@]} " =~ " ${new_stream} " ]]; then
        echo "Log stream '$new_stream' already exists!"
        return 1
    fi
    
    # Add to the array (this will be temporary for current session)
    AWS_LOG_STREAMS+=("$new_stream")
    echo "Added temporary log stream: $new_stream"
    echo "To make it permanent, add it to the AWS_LOG_STREAMS array in this file"
}

# Function to list all available streams
bb_aws_list() {
    echo "Available AWS log streams:"
    printf '%s\n' "${AWS_LOG_STREAMS[@]}" | nl
}

# Function to set default time range
bb_aws_since() {
    if [ -z "$1" ]; then
        echo "Current default time range: $AWS_LOG_SINCE"
        echo "Usage: aws-set-since <time>"
        echo "Examples: 10m, 1h, 2d, 1w"
        echo "Supported formats: m (minutes), h (hours), d (days), w (weeks)"
        return 1
    fi
    
    # Validate time format
    case "$1" in
        *m|*h|*d|*w)
            AWS_LOG_SINCE="$1"
            echo "Set default time range to: $AWS_LOG_SINCE"
            ;;
        *)
            echo "Invalid time format. Use: 10m, 1h, 2d, 1w"
            return 1
            ;;
    esac
}

# Detailed AWS logs with better formatting and colors
bb_aws_logs() {
    # Show all available log streams
    echo "Available AWS log streams:"
    printf '%s\n' "${AWS_LOG_STREAMS[@]}" | nl
    echo ""
    
    # Interactive selection of log stream
    local log_stream=$(printf '%s\n' "${AWS_LOG_STREAMS[@]}" | fzf --prompt="Select log stream: " --height=50% --layout=reverse --border)
    if [ -z "$log_stream" ]; then
        echo "No log stream selected"
        return 1
    fi
    
    # Ask for time range
    echo "Selected log stream: $log_stream"
    echo "Current default time: $AWS_LOG_SINCE"
    echo "Enter time range (e.g., 10m, 1h, 2d, 1w) or press Enter for default:"
    read -r since_input
    
    # Use input or default
    local since="${since_input:-$AWS_LOG_SINCE}"
    
    # Parse time format (m, h, d, w)
    case "$since" in
        *m) since="${since%m}m" ;;
        *h) since="${since%h}h" ;;
        *d) since="${since%d}d" ;;
        *w) since="${since%w}w" ;;
        *) since="${since}m" ;;  # Default to minutes if no suffix
    esac
    
    echo "Fetching detailed logs from: $log_stream (since: $since)"
    local cmd_tail="aws logs tail '$log_stream' --since '$since' --format short | pv -l | awk '{
        # Extract timestamp, level, and message
        timestamp = \$1 \" \" \$2
        level = \$3
        message = \$0
        gsub(/^[^ ]+ [^ ]+ [^ ]+ /, \"\", message)
        
        # Simple format: timestamp | level | message
        print timestamp \" | \" level \" | \" message
    }' > /tmp/aws_logs_detailed.txt"
    
    bb_confirm "$cmd_tail" || return $?
    
    fzf --preview 'tail -n +$(( {n} - 10 )) /tmp/aws_logs_detailed.txt | head -20' \
        --preview-window=right:70%:wrap \
        --bind 'ctrl-e:execute(NVIM_APPNAME=LazyVIM nvim /tmp/aws_logs_detailed.txt +{n})' \
        --bind 'ctrl-f:execute(grep -n "ERROR" /tmp/aws_logs_detailed.txt | fzf)' \
        --bind 'ctrl-w:execute(grep -n "WARN" /tmp/aws_logs_detailed.txt | fzf)' \
        --bind 'ctrl-i:execute(grep -n "INFO" /tmp/aws_logs_detailed.txt | fzf)' \
        < /tmp/aws_logs_detailed.txt
}

#!/bin/bash

# UK Legislation File Downloader
# Downloads all PDFs and plain text files for legislation from CSV data

set +e  # Don't exit on errors

# Configuration
DATA_CSV="all.csv"  # Default CSV file to read from
PDFS_DIR="pdfs"
PLAIN_DIR="plain"
LOG_FILE="download.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to safely create filename from URL and metadata
create_safe_filename() {
    local url="$1"
    local extension="$2"
    local year="$3"
    local num="$4"
    local name="$5"
    
    # Clean the name for filename use (remove quotes, special chars, limit length)
    local clean_name=$(echo "$name" | sed 's/^"//; s/"$//' | sed 's/[^a-zA-Z0-9 ]//g' | sed 's/ /_/g' | cut -c1-60)
    
    # Create descriptive filename using metadata for both PDF and HTML
    echo "${year}_${num}_${clean_name}.${extension}"
}

# Function to download a file with retry logic and better timeout handling
download_file() {
    local url="$1"
    local output_path="$2"
    local max_retries=3
    
    # Skip if file already exists and is not empty
    if [ -f "$output_path" ] && [ -s "$output_path" ]; then
        return 0  # Success - file already exists
    fi
    
    for attempt in $(seq 1 $max_retries); do
        # Use more aggressive timeout settings to prevent hanging
        local http_code
        
        # Add timeout command as additional safety measure
        timeout 180s curl -L -s -w "%{http_code}" \
            --connect-timeout 15 \
            --max-time 60 \
            --speed-time 30 \
            --speed-limit 1024 \
            --retry 1 \
            --retry-delay 2 \
            --retry-max-time 60 \
            --fail-with-body \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36)" \
            -o "$output_path" \
            "$url" 2>/dev/null
        
        http_code=$?
        
        # If timeout command killed curl, treat as timeout
        if [ $http_code -eq 124 ]; then
            print_warning "Download timeout for $url (attempt $attempt)"
            rm -f "$output_path"
            if [ $attempt -lt $max_retries ]; then
                sleep 5
                continue
            else
                return 1
            fi
        fi
        
        # Get actual HTTP code from curl output
        if [ -f "$output_path" ]; then
            # Check file size - if it's suspiciously small, it might be an error page
            local file_size=$(stat -f%z "$output_path" 2>/dev/null || stat -c%s "$output_path" 2>/dev/null || echo 0)
            
            # Check if download was successful (file exists, has content, reasonable size)
            if [ -s "$output_path" ] && [ "$file_size" -gt 100 ]; then
                return 0  # Success
            else
                print_warning "Downloaded file too small or empty: $output_path ($file_size bytes)"
                rm -f "$output_path"
            fi
        fi
        
        print_warning "Download failed for $url (attempt $attempt)"
        rm -f "$output_path"
        
        if [ $attempt -lt $max_retries ]; then
            print_warning "Retrying in 3 seconds..."
            sleep 3
        fi
    done
    
    print_error "Failed to download after $max_retries attempts: $url"
    return 1  # Failure
}

# Function to process a specific year with progress tracking
process_year() {
    local year="$1"
    local csv_file="$2"
    
    print_status "Processing year $year..."
    
    # Create directories for this year
    local year_pdf_dir="$PDFS_DIR/$year"
    local year_plain_dir="$PLAIN_DIR/$year"
    
    if ! mkdir -p "$year_pdf_dir" || ! mkdir -p "$year_plain_dir"; then
        print_error "Failed to create directories for year $year"
        return 1
    fi
    
    # Counters for this year
    local total_items=0
    local pdf_downloaded=0
    local pdf_failed=0
    local plain_downloaded=0
    local plain_failed=0
    local pdf_skipped=0
    local plain_skipped=0
    
    # Create temporary file for this year's data to avoid CSV parsing issues
    local temp_csv="/tmp/year_${year}_$$.csv"
    grep "^$year," "$csv_file" > "$temp_csv"
    
    if [ ! -s "$temp_csv" ]; then
        print_warning "No data found for year $year"
        rm -f "$temp_csv"
        return 0
    fi
    
    local total_lines=$(wc -l < "$temp_csv")
    print_status "Found $total_lines items for year $year"
    
    # Process CSV file for this year with better parsing
    local line_num=0
    while IFS= read -r line; do
        ((line_num++))
        
        # Skip empty lines
        if [ -z "$line" ]; then
            continue
        fi
        
        # Parse CSV line more carefully
        local csv_year=$(echo "$line" | cut -d',' -f1 | sed 's/^"//; s/"$//' | tr -d '\n\r')
        local num=$(echo "$line" | cut -d',' -f2 | sed 's/^"//; s/"$//' | tr -d '\n\r')
        local name=$(echo "$line" | cut -d',' -f3 | sed 's/^"//; s/"$//' | tr -d '\n\r')
        local page_url=$(echo "$line" | cut -d',' -f4 | sed 's/^"//; s/"$//' | tr -d '\n\r')
        local pdf_url=$(echo "$line" | cut -d',' -f6 | sed 's/^"//; s/"$//' | tr -d '\n\r')
        local pdf_available=$(echo "$line" | cut -d',' -f10 | sed 's/^"//; s/"$//' | tr -d '\n\r')
        
        # Construct plain URL
        local plain_url=""
        if [[ "$page_url" =~ ^https?:// ]]; then
            plain_url="${page_url%/}/data.xht"
        fi
        
        ((total_items++))
        
        # Progress indicator with more detail
        if [ $((total_items % 5)) -eq 0 ] || [ $total_items -le 5 ]; then
            print_status "Processing item $total_items/$total_lines for year $year..."
        fi
        
        # Download PDF if available
        if [ "$pdf_available" = "True" ] && [ -n "$pdf_url" ] && [ "$pdf_url" != "None" ]; then
            local pdf_filename=$(create_safe_filename "$pdf_url" "pdf" "$csv_year" "$num" "$name")
            local pdf_path="$year_pdf_dir/$pdf_filename"
            
            download_file "$pdf_url" "$pdf_path"
            local pdf_result=$?
            
            case $pdf_result in
                0)
                    ((pdf_downloaded++))
                    ;;
                *)
                    ((pdf_failed++))
                    echo "$csv_year,$num,\"$name\",$pdf_url,PDF,FAILED" >> "${LOG_FILE%.log}_failures.csv"
                    ;;
            esac
        else
            ((pdf_skipped++))
        fi
        
        # Download plain text if available
        if [ -n "$plain_url" ]; then
            local plain_filename=$(create_safe_filename "$plain_url" "html" "$csv_year" "$num" "$name")
            local plain_path="$year_plain_dir/$plain_filename"
            
            download_file "$plain_url" "$plain_path"
            local plain_result=$?
            
            # Check for empty or stub .xht file
            if [ $plain_result -eq 0 ] && [ -f "$plain_path" ]; then
                if [ ! -s "$plain_path" ]; then
                    print_warning "Empty HTML file: $plain_path"
                    rm -f "$plain_path"
                    plain_result=1
                elif grep -q -i "<html[^>]*>\s*</html>" "$plain_path" 2>/dev/null; then
                    print_warning "Stub HTML content in: $plain_path"
                    rm -f "$plain_path"
                    plain_result=1
                fi
            fi
            
            case $plain_result in
                0)
                    ((plain_downloaded++))
                    ;;
                *)
                    ((plain_failed++))
                    echo "$csv_year,$num,\"$name\",$plain_url,HTML,FAILED" >> "${LOG_FILE%.log}_failures.csv"
                    ;;
            esac
        else
            ((plain_skipped++))
        fi
        
    done < "$temp_csv"
    
    # Clean up temp file
    rm -f "$temp_csv"
    
    # Print summary for this year
    print_status "Year $year summary:"
    echo "  Total items: $total_items"
    echo "  PDFs: $pdf_downloaded downloaded, $pdf_failed failed, $pdf_skipped skipped/unavailable"
    echo "  Plain: $plain_downloaded downloaded, $plain_failed failed, $plain_skipped skipped/unavailable"
    
    # Log to file
    echo "$(date): Year $year - Total: $total_items, PDFs: $pdf_downloaded/$((pdf_downloaded + pdf_failed + pdf_skipped)), Plain: $plain_downloaded/$((plain_downloaded + plain_failed + plain_skipped))" >> "$LOG_FILE"
    
    return 0
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --year YEAR        Download files for specific year (e.g., --year 2020)"
    echo "  --all              Download files for all years in CSV"
    echo "  --csv FILE         Use specific CSV file (default: all.csv)"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --year 2020                    # Download 2020 files from all.csv"
    echo "  $0 --all                          # Download all years from all.csv"
    echo "  $0 --year 2020 --csv my_data.csv # Download 2020 files from my_data.csv"
    echo ""
    echo "Output directories:"
    echo "  pdfs/YEAR/         PDF files"
    echo "  plain/YEAR/        Plain text HTML files"
    echo ""
    echo "Dependencies:"
    echo "  - curl (required)"
    echo "  - timeout (recommended)"
}

# Check for required commands
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    if ! command -v timeout >/dev/null 2>&1; then
        print_warning "timeout command not found - downloads may hang longer"
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

# Parse command line arguments
YEAR=""
ALL_YEARS=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --year)
            YEAR="$2"
            shift 2
            ;;
        --all)
            ALL_YEARS=true
            shift
            ;;
        --csv)
            DATA_CSV="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate inputs - require either --year or --all
if [ -z "$YEAR" ] && [ "$ALL_YEARS" = false ]; then
    print_error "Either --year YEAR or --all is required"
    show_usage
    exit 1
fi

if [ -n "$YEAR" ] && [ "$ALL_YEARS" = true ]; then
    print_error "Cannot use both --year and --all options together"
    show_usage
    exit 1
fi

if [ ! -f "$DATA_CSV" ]; then
    print_error "CSV file not found: $DATA_CSV"
    exit 1
fi

# Check dependencies
check_dependencies

# Validate year format if specific year provided
if [ -n "$YEAR" ]; then
    if ! [[ "$YEAR" =~ ^[0-9]{4}$ ]]; then
        print_error "Year must be a 4-digit number (e.g., 2025)"
        exit 1
    fi
    
    # Check if year exists in CSV
    if ! grep -q "^$YEAR," "$DATA_CSV"; then
        print_error "Year $YEAR not found in $DATA_CSV"
        print_status "Available years:"
        cut -d',' -f1 "$DATA_CSV" | grep -E '^[0-9]{4}$' | sort -u | head -10
        exit 1
    fi
fi

# Get list of years to process
if [ "$ALL_YEARS" = true ]; then
    # Get all unique years from the CSV
    YEARS_TO_PROCESS=($(cut -d',' -f1 "$DATA_CSV" | grep -E '^[0-9]{4}$' | sort -n | uniq))
    if [ ${#YEARS_TO_PROCESS[@]} -eq 0 ]; then
        print_error "No valid years found in $DATA_CSV"
        exit 1
    fi
    
    # Show the actual range found
    first_year=${YEARS_TO_PROCESS[0]}
    last_year=${YEARS_TO_PROCESS[-1]}
    print_status "Found ${#YEARS_TO_PROCESS[@]} years to process ($first_year-$last_year)"
else
    YEARS_TO_PROCESS=("$YEAR")
fi

# Main execution
print_status "UK Legislation File Downloader"
print_status "==============================="
if [ "$ALL_YEARS" = true ]; then
    print_status "Processing all years: ${YEARS_TO_PROCESS[*]}"
else
    print_status "Year: $YEAR"
fi
print_status "CSV file: $DATA_CSV"
print_status "PDF directory: $PDFS_DIR"
print_status "Plain directory: $PLAIN_DIR"
print_status "Log file: $LOG_FILE"
print_status ""

# Initialize log
echo "Download session started at $(date)" >> "$LOG_FILE"
echo "year,num,name,url,type,status" > "${LOG_FILE%.log}_failures.csv"

# Create base directories
mkdir -p "$PDFS_DIR"
mkdir -p "$PLAIN_DIR"

# Add signal handling to allow graceful interruption
trap 'print_warning "Download interrupted by user"; exit 130' INT TERM

# Process all years
start_time=$(date +%s)
total_years=${#YEARS_TO_PROCESS[@]}
current_year=1

for year_to_process in "${YEARS_TO_PROCESS[@]}"; do
    if [ "$ALL_YEARS" = true ]; then
        print_status "Processing year $year_to_process ($current_year/$total_years)..."
    fi
    
    if process_year "$year_to_process" "$DATA_CSV"; then
        if [ "$ALL_YEARS" = true ]; then
            print_success "Completed year $year_to_process ($current_year/$total_years)"
        fi
    else
        print_error "Failed to process year $year_to_process"
        if [ "$ALL_YEARS" = false ]; then
            exit 1
        fi
    fi
    
    ((current_year++))
done

end_time=$(date +%s)
duration=$((end_time - start_time))
minutes=$((duration / 60))
seconds=$((duration % 60))

if [ "$ALL_YEARS" = true ]; then
    print_success "Download completed for all years in ${minutes}m ${seconds}s"
    
    # Show overall statistics
    if command -v du >/dev/null 2>&1; then
        total_pdf_size=$(du -sh "$PDFS_DIR" 2>/dev/null | cut -f1 || echo "N/A")
        total_plain_size=$(du -sh "$PLAIN_DIR" 2>/dev/null | cut -f1 || echo "N/A")
        print_status "Total directory sizes: PDFs=$total_pdf_size, Plain=$total_plain_size"
    fi
    
    # Count all files
    total_pdf_count=$(find "$PDFS_DIR" -type f -name "*.pdf" 2>/dev/null | wc -l)
    total_plain_count=$(find "$PLAIN_DIR" -type f -name "*.html" 2>/dev/null | wc -l)
    print_status "Total files downloaded: $total_pdf_count PDFs, $total_plain_count HTML files across ${#YEARS_TO_PROCESS[@]} years"
else
    print_success "Download completed for year $YEAR in ${minutes}m ${seconds}s"
    
    # Show directory sizes
    if command -v du >/dev/null 2>&1; then
        pdf_size=$(du -sh "$PDFS_DIR/$YEAR" 2>/dev/null | cut -f1 || echo "N/A")
        plain_size=$(du -sh "$PLAIN_DIR/$YEAR" 2>/dev/null | cut -f1 || echo "N/A")
        print_status "Directory sizes: PDFs=$pdf_size, Plain=$plain_size"
    fi
    
    # Count files
    pdf_count=$(find "$PDFS_DIR/$YEAR" -type f -name "*.pdf" 2>/dev/null | wc -l)
    plain_count=$(find "$PLAIN_DIR/$YEAR" -type f -name "*.html" 2>/dev/null | wc -l)
    print_status "Files downloaded: $pdf_count PDFs, $plain_count HTML files"
fi

print_success "All downloads completed!"
print_status "Check $LOG_FILE for detailed log information."

# Show failure summary
failure_count=$(tail -n +2 "${LOG_FILE%.log}_failures.csv" 2>/dev/null | wc -l)
if [ "$failure_count" -gt 0 ]; then
    print_warning "$failure_count download failures logged in ${LOG_FILE%.log}_failures.csv"
fi
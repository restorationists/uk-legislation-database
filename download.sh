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

# Function to safely create filename from URL
create_safe_filename() {
    local url="$1"
    local extension="$2"
    
    # Extract the path part and create a safe filename
    local filename=$(basename "$url" | sed 's/[^a-zA-Z0-9._-]/_/g')
    
    # If filename is empty or just extension, create from URL path
    if [ -z "$filename" ] || [ "$filename" = "$extension" ]; then
        filename=$(echo "$url" | sed 's|.*/||' | sed 's/[^a-zA-Z0-9._-]/_/g')
    fi
    
    # Ensure it has the right extension
    if [[ ! "$filename" =~ \.$extension$ ]]; then
        filename="${filename}.${extension}"
    fi
    
    echo "$filename"
}

# Function to download a file with retry logic
download_file() {
    local url="$1"
    local output_path="$2"
    local max_retries=3
    
    # Skip if file already exists and is not empty
    if [ -f "$output_path" ] && [ -s "$output_path" ]; then
        return 0  # Success - file already exists
    fi
    
    for attempt in $(seq 1 $max_retries); do
        if curl -L -s -f --connect-timeout 30 --max-time 120 -o "$output_path" "$url"; then
            if [ -f "$output_path" ] && [ -s "$output_path" ]; then
                return 0  # Success
            else
                print_warning "Downloaded file is empty: $output_path"
                rm -f "$output_path"
            fi
        fi
        
        if [ $attempt -lt $max_retries ]; then
            print_warning "Download attempt $attempt failed for $url, retrying..."
            sleep 2
        fi
    done
    
    print_error "Failed to download after $max_retries attempts: $url"
    return 1  # Failure
}

# Function to process a specific year
process_year() {
    local year="$1"
    local csv_file="$2"
    
    print_status "Processing year $year..."
    
    # Create directories for this year
    local year_pdf_dir="$PDFS_DIR/$year"
    local year_plain_dir="$PLAIN_DIR/$year"
    
    mkdir -p "$year_pdf_dir"
    mkdir -p "$year_plain_dir"
    
    # Counters for this year
    local total_items=0
    local pdf_downloaded=0
    local pdf_failed=0
    local plain_downloaded=0
    local plain_failed=0
    local pdf_skipped=0
    local plain_skipped=0
    
    # Process CSV file for this year
    # Skip header line and filter by year
    while IFS=',' read -r csv_year num name page_url plain_url pdf_url legislation_type act_type page_available plain_available pdf_available; do
        # Skip header or empty lines
        if [ "$csv_year" = "year" ] || [ -z "$csv_year" ]; then
            continue
        fi
        
        # Only process matching year
        if [ "$csv_year" != "$year" ]; then
            continue
        fi
        
        ((total_items++))
        
        # Clean up the name for logging (remove quotes)
        clean_name=$(echo "$name" | sed 's/^"//; s/"$//')
        
        # Download PDF if available
        if [ "$pdf_available" = "True" ] && [ -n "$pdf_url" ] && [ "$pdf_url" != "None" ]; then
            pdf_filename=$(create_safe_filename "$pdf_url" "pdf")
            pdf_path="$year_pdf_dir/$pdf_filename"
            
            if download_file "$pdf_url" "$pdf_path"; then
                ((pdf_downloaded++))
            else
                ((pdf_failed++))
            fi
        else
            ((pdf_skipped++))
        fi
        
        # Download plain text if available
        if [ "$plain_available" = "True" ] && [ -n "$plain_url" ] && [ "$plain_url" != "None" ]; then
            plain_filename=$(create_safe_filename "$plain_url" "html")
            plain_path="$year_plain_dir/$plain_filename"
            
            if download_file "$plain_url" "$plain_path"; then
                ((plain_downloaded++))
            else
                ((plain_failed++))
            fi
        else
            ((plain_skipped++))
        fi
        
        # Progress indicator
        if [ $((total_items % 10)) -eq 0 ]; then
            print_status "Processed $total_items items for year $year..."
        fi
        
    done < "$csv_file"
    
    # Print summary for this year
    print_status "Year $year summary:"
    echo "  Total items: $total_items"
    echo "  PDFs: $pdf_downloaded downloaded, $pdf_failed failed, $pdf_skipped skipped"
    echo "  Plain: $plain_downloaded downloaded, $plain_failed failed, $plain_skipped skipped"
    
    # Log to file
    echo "$(date): Year $year - Total: $total_items, PDFs: $pdf_downloaded/$((pdf_downloaded + pdf_failed + pdf_skipped)), Plain: $plain_downloaded/$((plain_downloaded + plain_failed + plain_skipped))" >> "$LOG_FILE"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --year YEAR        Download files for specific year (e.g., --year 2020)"
    echo "  --csv FILE         Use specific CSV file (default: all.csv)"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --year 2020                    # Download 2020 files from all.csv"
    echo "  $0 --year 2020 --csv my_data.csv # Download 2020 files from my_data.csv"
    echo ""
    echo "Output directories:"
    echo "  pdfs/YEAR/         PDF files"
    echo "  plain/YEAR/        Plain text HTML files"
}

# Parse command line arguments
YEAR=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --year)
            YEAR="$2"
            shift 2
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

# Validate inputs
if [ -z "$YEAR" ]; then
    print_error "Year is required. Use --year YEAR"
    show_usage
    exit 1
fi

if [ ! -f "$DATA_CSV" ]; then
    print_error "CSV file not found: $DATA_CSV"
    exit 1
fi

# Check if curl is available
if ! command -v curl >/dev/null 2>&1; then
    print_error "curl is required but not installed. Please install curl."
    exit 1
fi

# Main execution
print_status "UK Legislation File Downloader"
print_status "==============================="
print_status "Year: $YEAR"
print_status "CSV file: $DATA_CSV"
print_status "PDF directory: $PDFS_DIR/$YEAR"
print_status "Plain directory: $PLAIN_DIR/$YEAR"
print_status "Log file: $LOG_FILE"
print_status ""

# Initialize log
echo "Download session started at $(date)" >> "$LOG_FILE"

# Create base directories
mkdir -p "$PDFS_DIR"
mkdir -p "$PLAIN_DIR"

# Process the year
start_time=$(date +%s)
process_year "$YEAR" "$DATA_CSV"
end_time=$(date +%s)

duration=$((end_time - start_time))
minutes=$((duration / 60))
seconds=$((duration % 60))

print_success "Download completed for year $YEAR in ${minutes}m ${seconds}s"

# Show directory sizes
if command -v du >/dev/null 2>&1; then
    pdf_size=$(du -sh "$PDFS_DIR/$YEAR" 2>/dev/null | cut -f1 || echo "N/A")
    plain_size=$(du -sh "$PLAIN_DIR/$YEAR" 2>/dev/null | cut -f1 || echo "N/A")
    print_status "Directory sizes: PDFs=$pdf_size, Plain=$plain_size"
fi

# Count files
pdf_count=$(find "$PDFS_DIR/$YEAR" -type f -name "*.pdf" | wc -l)
plain_count=$(find "$PLAIN_DIR/$YEAR" -type f -name "*.html" | wc -l)
print_status "Files downloaded: $pdf_count PDFs, $plain_count HTML files"

print_success "All downloads completed!"
print_status "Check $LOG_FILE for detailed log information."
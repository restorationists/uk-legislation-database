#!/bin/bash

# UK Legislation Scraper - Complete Historical Database (1900-2025)
# This script scrapes all UK primary legislation from 1900 to 2025

# Don't exit on errors - we want to handle them gracefully
set +e

# Configuration
START_YEAR=1900
END_YEAR=2025
DATA_DIR="data"
SCRAPER_SCRIPT="scrape.py"
FINAL_OUTPUT="all.csv"
LOG_FILE="scrape_all.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Trap SIGINT (Ctrl+C) to allow graceful exit
trap 'print_warning "Interrupted by user (Ctrl+C). Current progress saved."; cleanup_and_exit' INT

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

# Function to handle cleanup and exit
cleanup_and_exit() {
    echo
    print_status "═══════════════════════════════════════════════════════════════"
    print_warning "Script interrupted. Current progress:"
    print_status "Successfully processed: $successful_years years"
    if [ $failed_years -gt 0 ]; then
        print_warning "Failed: $failed_years years"
    fi
    print_status "Total records collected so far: $total_records"
    
    # Create partial concatenation if we have any successful files
    if [ ${#successful_files[@]} -gt 0 ]; then
        partial_output="partial_all.csv"
        print_status "Creating partial output: $partial_output"
        
        # Start with header from first file
        head -n 1 "${successful_files[0]}" > "$partial_output"
        
        # Append all data (skip headers)
        for file in "${successful_files[@]}"; do
            tail -n +2 "$file" >> "$partial_output"
        done
        
        partial_records=$(($(wc -l < "$partial_output") - 1))
        partial_size=$(get_file_size "$partial_output")
        print_success "Created $partial_output with $partial_records records ($partial_size)"
    fi
    
    print_status "To resume, run the script again. Completed years will be skipped."
    print_status "═══════════════════════════════════════════════════════════════"
    exit 0
}

# Function to calculate estimated time
calculate_eta() {
    local current_year=$1
    local start_time=$2
    local years_completed=$((current_year - START_YEAR))
    local total_years=$((END_YEAR - START_YEAR + 1))
    
    if [ $years_completed -gt 0 ]; then
        local elapsed=$(($(date +%s) - start_time))
        local avg_time_per_year=$((elapsed / years_completed))
        local remaining_years=$((total_years - years_completed))
        local eta_seconds=$((remaining_years * avg_time_per_year))
        
        local eta_hours=$((eta_seconds / 3600))
        local eta_minutes=$(((eta_seconds % 3600) / 60))
        
        echo "ETA: ${eta_hours}h ${eta_minutes}m (${years_completed}/${total_years} years complete)"
    else
        echo "Calculating ETA..."
    fi
}

# Function to get file size in human readable format
get_file_size() {
    if [ -f "$1" ]; then
        if command -v numfmt >/dev/null 2>&1; then
            echo "$(numfmt --to=iec-i --suffix=B $(wc -c < "$1"))"
        else
            echo "$(wc -c < "$1") bytes"
        fi
    else
        echo "0 bytes"
    fi
}

# Check if scraper script exists
if [ ! -f "$SCRAPER_SCRIPT" ]; then
    print_error "Scraper script '$SCRAPER_SCRIPT' not found!"
    print_error "Please ensure the scraper script is in the current directory."
    exit 1
fi

# Check Python dependencies
print_status "Checking Python dependencies..."
python3 -c "import requests, bs4, csv, argparse" 2>/dev/null || {
    print_error "Missing Python dependencies. Please install: pip3 install requests beautifulsoup4"
    exit 1
}

# Create data directory
print_status "Creating data directory..."
mkdir -p "$DATA_DIR"

# Initialize log file
echo "UK Legislation Scraper Log - Started at $(date)" > "$LOG_FILE"

# Start timing
start_time=$(date +%s)
print_status "Starting comprehensive scrape from $START_YEAR to $END_YEAR"
print_status "Data will be saved in: $DATA_DIR/"
print_status "Final output: $FINAL_OUTPUT"
print_status "Log file: $LOG_FILE"
print_warning "Press Ctrl+C to stop gracefully at any time"

# Initialize counters
successful_years=0
failed_years=0
total_records=0

# Array to keep track of successful files for concatenation
successful_files=()

# Main scraping loop
for year in $(seq $START_YEAR $END_YEAR); do
    output_file="$DATA_DIR/uk_legislation_${year}.csv"
    
    print_status "Processing year $year..."
    echo "Processing year $year at $(date)" >> "$LOG_FILE"
    
    # Show progress and ETA
    if [ $year -gt $START_YEAR ]; then
        eta_info=$(calculate_eta $year $start_time)
        print_status "$eta_info"
    fi
    
    # Skip if file already exists and is not empty
    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        file_size=$(get_file_size "$output_file")
        print_warning "Year $year already exists ($file_size), skipping..."
        successful_files+=("$output_file")
        ((successful_years++))
        
        # Still count records for progress tracking
        year_records=$(($(wc -l < "$output_file") - 1))
        total_records=$((total_records + year_records))
        continue
    fi
    
    # Run the scraper for this year with live output
    print_status "Running: python3 $SCRAPER_SCRIPT --year $year --output $output_file"
    
    # Use a more robust approach to capture exit code
    python3 "$SCRAPER_SCRIPT" --year "$year" --output "$output_file" 2>&1 | tee -a "$LOG_FILE"
    exit_code=${PIPESTATUS[0]}
    
    if [ $exit_code -eq 0 ]; then
        if [ -f "$output_file" ] && [ -s "$output_file" ]; then
            # Count records (subtract 1 for header)
            year_records=$(($(wc -l < "$output_file") - 1))
            total_records=$((total_records + year_records))
            file_size=$(get_file_size "$output_file")
            
            print_success "Year $year completed: $year_records records ($file_size)"
            successful_files+=("$output_file")
            ((successful_years++))
        else
            print_warning "Year $year: No data found or empty file"
            ((failed_years++))
        fi
    else
        print_error "Year $year: Scraping failed (exit code: $exit_code)"
        echo "FAILED: Year $year at $(date) (exit code: $exit_code)" >> "$LOG_FILE"
        ((failed_years++))
    fi
    
    # Small delay between years to be respectful to the server
    sleep 2
done

# Print summary statistics
end_time=$(date +%s)
total_duration=$((end_time - start_time))
hours=$((total_duration / 3600))
minutes=$(((total_duration % 3600) / 60))

print_status "Scraping completed!"
print_status "═══════════════════════════════════════════════════════════════"
print_success "Successfully processed: $successful_years years"
if [ $failed_years -gt 0 ]; then
    print_warning "Failed: $failed_years years"
fi
print_status "Total records collected: $total_records"
print_status "Total time: ${hours}h ${minutes}m"
print_status "═══════════════════════════════════════════════════════════════"

# Concatenate all successful files
if [ ${#successful_files[@]} -gt 0 ]; then
    print_status "Concatenating all files into $FINAL_OUTPUT..."
    
    # Start with header from first file
    head -n 1 "${successful_files[0]}" > "$FINAL_OUTPUT"
    
    # Append all data (skip headers)
    for file in "${successful_files[@]}"; do
        tail -n +2 "$file" >> "$FINAL_OUTPUT"
    done
    
    # Final statistics
    final_records=$(($(wc -l < "$FINAL_OUTPUT") - 1))
    final_size=$(get_file_size "$FINAL_OUTPUT")
    
    print_success "Created $FINAL_OUTPUT with $final_records total records ($final_size)"
    
    # Show top legislation types summary
    print_status "Top legislation types:"
    tail -n +2 "$FINAL_OUTPUT" | cut -d',' -f7 | sort | uniq -c | sort -nr | head -5 | while read count type; do
        echo "  $count × $type"
    done
    
else
    print_error "No successful files to concatenate!"
    exit 1
fi

# Optional: Create a summary report
summary_file="scraping_summary.txt"
cat > "$summary_file" << EOF
UK Legislation Scraping Summary
===============================
Date: $(date)
Period: $START_YEAR - $END_YEAR
Duration: ${hours}h ${minutes}m

Results:
- Successful years: $successful_years
- Failed years: $failed_years
- Total records: $final_records
- Final file size: $final_size

Files created:
- Individual year files: $DATA_DIR/uk_legislation_YYYY.csv
- Combined file: $FINAL_OUTPUT
- Log file: $LOG_FILE
- This summary: $summary_file

Availability Summary:
EOF

# Add availability statistics if the final file exists
if [ -f "$FINAL_OUTPUT" ]; then
    echo "- Available pages: $(tail -n +2 "$FINAL_OUTPUT" | cut -d',' -f9 | grep -c "True") / $final_records" >> "$summary_file"
    echo "- Available plain URLs: $(tail -n +2 "$FINAL_OUTPUT" | cut -d',' -f10 | grep -c "True") / $final_records" >> "$summary_file"
    echo "- Available PDF URLs: $(tail -n +2 "$FINAL_OUTPUT" | cut -d',' -f11 | grep -c "True") / $final_records" >> "$summary_file"
fi

print_success "Summary report created: $summary_file"

# Optional cleanup prompt
echo
read -p "Do you want to keep individual year files in $DATA_DIR/? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Cleaning up individual files..."
    rm -f $DATA_DIR/uk_legislation_*.csv
    print_success "Individual files removed. Combined data is in $FINAL_OUTPUT"
fi

print_success "Script completed successfully!"
echo "Final output: $FINAL_OUTPUT ($final_records records, $final_size)"
# UK Legislation Scraper

A comprehensive tool to scrape and compile UK primary legislation data from 1900-2025 from [legislation.gov.uk](https://www.legislation.gov.uk).

## 📁 Files

- `scrape.py` - Python scraper for individual years
- `run.sh` - Bash script to scrape all years (1900-2025)

## 🚀 Quick Start

### Prerequisites
```bash
# Install Python dependencies
pip3 install requests beautifulsoup4

# Make scripts executable
chmod +x run.sh
```

### Single Year Scraping
```bash
# Scrape one year
python3 scrape.py --year 2020 --output my_2020_data.csv

# Test mode (first 5 items only)
python3 scrape.py --year 2020 --test

# See all options
python3 scrape.py --help
```

### Complete Historical Database (1900-2025)
```bash
# Scrape all 126 years
./run.sh

# Output:
# - data/uk_legislation_YYYY.csv (individual years)
# - all.csv (combined 125+ years)
# - scrape_all.log (detailed log)
# - scraping_summary.txt (final report)
```

## ⚡ Features

### Python Scraper (`scrape.py`)
- **URL Validation**: Checks if pages/PDFs actually exist (HEAD requests)
- **Multiple Formats**: Extracts page URLs, plain text URLs, and PDF URLs
- **All Legislatures**: UK Parliament, Scottish Parliament, Welsh Senedd, Northern Ireland Assembly, Church Measures
- **Smart Parsing**: Handles different numbering systems (c. 25, asp 18, etc.)
- **Robust**: Retry logic, timeouts, comprehensive error handling

### Bash Controller (`scrape_all_years.sh`)
- **Graceful Interruption**: Press `Ctrl+C` to stop safely, resume later
- **Live Output**: See Python progress in real-time
- **Auto-Resume**: Skips already completed years
- **Progress Tracking**: ETA calculations, file sizes, record counts
- **Smart Concatenation**: Combines all individual files into one master CSV

## 📊 Output Format

```csv
year,num,name,page_url,plain_url,pdf_url,legislation_type,act_type,page_url_available,plain_url_available,pdf_url_available
2020,29,European Union (Future Relationship) Act 2020,https://...,https://...,https://...,UK Public General Acts,General,True,True,True
```

### Columns Explained
- **year/num/name**: Basic legislation info
- **page_url**: Main legislation page
- **plain_url**: Plain text view (`?view=plain`)  
- **pdf_url**: Official PDF version
- **legislation_type**: Full type (e.g., "UK Public General Acts")
- **act_type**: Simplified category (General/Local/Private)
- ***_available**: Boolean flags for URL validation

## 🛠 Usage Patterns

### Quick Test
```bash
# Test with recent year
python3 scrape.py --year 2023 --test --output test.csv
```

### Partial Range
```bash
# Modern era only (modify script START_YEAR/END_YEAR)
# or run individual years:
for year in {2000..2025}; do
    python3 scrape.py --year $year --output "data/uk_legislation_${year}.csv"
done
```

### Resume Interrupted Run
```bash
# Just run again - it will skip completed years
./scrape_all_years.sh
```

## ⏱ Expected Runtime

- **Single year**: 2-5 minutes (varies by legislation volume)
- **Complete run**: 4-10 hours for all 126 years
- **Early years (1900s)**: Faster (less legislation)
- **Modern years (2000s+)**: Slower (more legislation + devolved parliaments)

## 🎯 Tips

1. **Start Small**: Test with `--year 2020 --test` first
2. **Monitor Progress**: Watch live output for any issues
3. **Stable Connection**: Ensure reliable internet (script is resumable)
4. **Disk Space**: ~50-200MB for complete database
5. **Interruption**: Use `Ctrl+C` to stop gracefully, not kill/force quit

## 📈 Expected Results

- **~15,000-25,000 total records** across all years
- **High availability**: 95%+ of URLs should be working
- **Comprehensive coverage**: All UK primary legislation types
- **Quality data**: Validated URLs, proper categorization

## 🚨 Troubleshooting

### Common Issues
```bash
# Missing dependencies
pip3 install requests beautifulsoup4

# Permission denied
chmod +x run.sh

# Script not found
# Ensure scrape.py is in same directory as run.sh
```

### If Scraping Stalls
- Press `Ctrl+C` to stop gracefully
- Check `scrape_all.log` for error details
- Resume by running script again
- Individual year timeout: 30 minutes

---

**Note**: This tool is designed to be respectful to legislation.gov.uk servers with built-in delays and reasonable request rates.
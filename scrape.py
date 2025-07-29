import requests
from bs4 import BeautifulSoup
import csv
import time
import re
from urllib.parse import urljoin, urlparse
import logging
import argparse

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class UKLegislationScraper:
    def __init__(self):
        self.base_url = "https://www.legislation.gov.uk"
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        })
        
    def get_page(self, url, max_retries=3):
        """Get a page with retry logic"""
        for attempt in range(max_retries):
            try:
                response = self.session.get(url, timeout=30)
                response.raise_for_status()
                return response
            except requests.RequestException as e:
                logger.warning(f"Attempt {attempt + 1} failed for {url}: {e}")
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                else:
                    logger.error(f"Failed to get {url} after {max_retries} attempts")
                    return None
    
    def check_url_exists(self, url, max_retries=2):
        """Check if a URL exists using HEAD request"""
        if not url:
            return False
            
        for attempt in range(max_retries):
            try:
                response = self.session.head(url, timeout=15, allow_redirects=True)
                if response.status_code == 200:
                    return True
                elif response.status_code == 404:
                    return False
                else:
                    # For other status codes, try a GET request as fallback
                    response = self.session.get(url, timeout=15)
                    return response.status_code == 200
            except requests.RequestException as e:
                logger.warning(f"Attempt {attempt + 1} failed checking {url}: {e}")
                if attempt < max_retries - 1:
                    time.sleep(1)
                else:
                    logger.error(f"Failed to check {url} after {max_retries} attempts")
                    return False
        
        return False
    
    def extract_legislation_info(self, row):
        """Extract legislation information from a table row"""
        try:
            cells = row.find_all('td')
            if len(cells) < 3:
                return None
                
            # Extract title and link
            title_cell = cells[0]
            title_link = title_cell.find('a')
            if not title_link:
                return None
                
            name = title_link.get_text(strip=True)
            page_url = urljoin(self.base_url, title_link.get('href', ''))
            
            # Extract year and number
            year_num_cell = cells[1]
            year_num_text = year_num_cell.get_text(strip=True)
            
            # Parse year and number from various formats:
            # "2020 c. 29" (UK Public General Acts)
            # "2020 asp 18" (Acts of the Scottish Parliament)
            # "1900 c. cclxix" (older numbering)
            year_match = re.search(r'(\d{4})', year_num_text)
            year = year_match.group(1) if year_match else None
            
            # Try different number patterns
            num = None
            
            # Pattern 1: "c. NUMBER" (traditional UK acts)
            num_match = re.search(r'c\.\s*([a-z]*\d+|[ivxlcdm]+)', year_num_text, re.IGNORECASE)
            if num_match:
                num = num_match.group(1)
            else:
                # Pattern 2: "asp NUMBER" (Scottish Parliament)
                num_match = re.search(r'asp\s+(\d+)', year_num_text, re.IGNORECASE)
                if num_match:
                    num = num_match.group(1)
                else:
                    # Pattern 3: "asc NUMBER" (Senedd Cymru)
                    num_match = re.search(r'asc\s+(\d+)', year_num_text, re.IGNORECASE)
                    if num_match:
                        num = num_match.group(1)
                    else:
                        # Pattern 4: "anaw NUMBER" (National Assembly for Wales)
                        num_match = re.search(r'anaw\s+(\d+)', year_num_text, re.IGNORECASE)
                        if num_match:
                            num = num_match.group(1)
                        else:
                            # Pattern 5: "nia NUMBER" (Northern Ireland Assembly)
                            num_match = re.search(r'nia\s+(\d+)', year_num_text, re.IGNORECASE)
                            if num_match:
                                num = num_match.group(1)
                            else:
                                # Pattern 6: "mwa NUMBER" (Measures of the National Assembly for Wales)
                                num_match = re.search(r'mwa\s+(\d+)', year_num_text, re.IGNORECASE)
                                if num_match:
                                    num = num_match.group(1)
                                else:
                                    # Pattern 7: "ukcm NUMBER" (Church Measures)
                                    num_match = re.search(r'ukcm\s+(\d+)', year_num_text, re.IGNORECASE)
                                    if num_match:
                                        num = num_match.group(1)
                                    else:
                                        # Pattern 8: Just extract any number at the end
                                        num_match = re.search(r'(\d+)\s*$', year_num_text)
                                        if num_match:
                                            num = num_match.group(1)
            
            # Extract legislation type
            type_cell = cells[2]
            leg_type = type_cell.get_text(strip=True)
            
            return {
                'year': year,
                'num': num,
                'name': name,
                'page_url': page_url,
                'type': leg_type
            }
        except Exception as e:
            logger.error(f"Error extracting legislation info: {e}")
            return None
    
    def get_pdf_url(self, page_url):
        """Extract PDF URL from legislation page and verify it exists"""
        try:
            response = self.get_page(page_url)
            if not response:
                return None
                
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Look for PDF links in the "More Resources" section
            pdf_links = soup.find_all('a', class_='pdfLink')
            if pdf_links:
                pdf_href = pdf_links[0].get('href')
                if pdf_href:
                    pdf_url = urljoin(self.base_url, pdf_href)
                    # Check if PDF actually exists
                    if self.check_url_exists(pdf_url):
                        return pdf_url
                    else:
                        logger.warning(f"PDF URL does not exist: {pdf_url}")
            
            # Alternative: look for any PDF link
            pdf_links = soup.find_all('a', href=re.compile(r'\.pdf$', re.IGNORECASE))
            if pdf_links:
                pdf_href = pdf_links[0].get('href')
                if pdf_href:
                    pdf_url = urljoin(self.base_url, pdf_href)
                    # Check if PDF actually exists
                    if self.check_url_exists(pdf_url):
                        return pdf_url
                    else:
                        logger.warning(f"Alternative PDF URL does not exist: {pdf_url}")
                        
            return None
        except Exception as e:
            logger.error(f"Error getting PDF URL from {page_url}: {e}")
            return None
    
    def construct_plain_url(self, page_url):
        """Construct the plain view URL and verify it exists"""
        try:
            # Convert from /ukpga/1974/51/contents/enacted to /ukpga/1974/51/contents?view=plain
            if '/contents/' in page_url:
                base_url = page_url.split('/contents/')[0]
                plain_url = f"{base_url}/contents?view=plain"
            elif page_url.endswith('/contents'):
                plain_url = f"{page_url}?view=plain"
            else:
                # Try to construct from the base URL
                if '/ukpga/' in page_url or '/ukla/' in page_url or '/ukppa/' in page_url or '/asp/' in page_url or '/asc/' in page_url or '/anaw/' in page_url or '/nia/' in page_url:
                    # Extract the base path
                    parts = page_url.split('/')
                    if len(parts) >= 5:
                        base_path = '/'.join(parts[:5])  # e.g., /ukpga/1974/51
                        plain_url = f"{base_path}/contents?view=plain"
                    else:
                        return None
                else:
                    return None
            
            # Check if the plain URL actually exists
            if self.check_url_exists(plain_url):
                return plain_url
            else:
                logger.warning(f"Plain URL does not exist: {plain_url}")
                return None
                
        except Exception as e:
            logger.error(f"Error constructing/checking plain URL for {page_url}: {e}")
            return None
    
    def scrape_year(self, year, include_secondary=False):
        """Scrape all legislation for a given year"""
        if include_secondary:
            logger.info(f"Scraping primary and secondary legislation for year {year}")
            url = f"{self.base_url}/primary+secondary/{year}"
        else:
            logger.info(f"Scraping primary legislation only for year {year}")
            url = f"{self.base_url}/primary/{year}"
            
        all_legislation = []
        page = 1
        
        while True:
            if page == 1:
                page_url = url
            else:
                page_url = f"{url}?page={page}"
                
            logger.info(f"Fetching page {page} for year {year}: {page_url}")
            
            response = self.get_page(page_url)
            if not response:
                break
                
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Find the results table
            content_div = soup.find('div', id='content')
            if not content_div:
                logger.warning(f"No content div found for {page_url}")
                break
                
            table = content_div.find('table')
            if not table:
                logger.warning(f"No table found for {page_url}")
                break
                
            tbody = table.find('tbody')
            if not tbody:
                logger.warning(f"No tbody found for {page_url}")
                break
                
            rows = tbody.find_all('tr')
            if not rows:
                logger.info(f"No more rows found on page {page}, stopping")
                break
                
            page_legislation = []
            for row in rows:
                leg_info = self.extract_legislation_info(row)
                if leg_info:
                    page_legislation.append(leg_info)
                    
            if not page_legislation:
                logger.info(f"No legislation found on page {page}, stopping")
                break
                
            all_legislation.extend(page_legislation)
            logger.info(f"Found {len(page_legislation)} items on page {page}")
            
            # Check if there's a next page
            if include_secondary:
                next_links = soup.find_all('a', href=re.compile(f'/primary\\+secondary/{year}\\?page={page + 1}'))
            else:
                next_links = soup.find_all('a', href=re.compile(f'/primary/{year}\\?page={page + 1}'))
            
            if not next_links:
                logger.info(f"No next page found after page {page}")
                break
                
            page += 1
            time.sleep(1)  # Be respectful to the server
            
        logger.info(f"Found total of {len(all_legislation)} items for year {year}")
        return all_legislation
    
    def enrich_with_urls(self, legislation_list):
        """Enrich legislation data with PDF and plain URLs, checking for availability"""
        logger.info(f"Enriching {len(legislation_list)} items with additional URLs and checking availability")
        
        for i, item in enumerate(legislation_list):
            logger.info(f"Processing item {i + 1}/{len(legislation_list)}: {item['name']}")
            
            # First check if the main page URL exists
            if self.check_url_exists(item['page_url']):
                # Get plain URL and check if it exists
                item['plain_url'] = self.construct_plain_url(item['page_url'])
                
                # Get PDF URL and check if it exists
                item['pdf_url'] = self.get_pdf_url(item['page_url'])
                
                # Mark main page as available
                item['page_url_available'] = True
            else:
                logger.warning(f"Main page URL does not exist: {item['page_url']}")
                item['page_url_available'] = False
                item['plain_url'] = None
                item['pdf_url'] = None
            
            # Add availability flags
            item['plain_url_available'] = item['plain_url'] is not None
            item['pdf_url_available'] = item['pdf_url'] is not None
            
            # Add some delay to be respectful
            if i % 10 == 0 and i > 0:
                time.sleep(2)
            else:
                time.sleep(0.5)
                
        return legislation_list
    
    def scrape_all_years(self, start_year=1990, end_year=2025, include_secondary=False):
        """Scrape all legislation from start_year to end_year"""
        all_legislation = []
        
        for year in range(start_year, end_year + 1):
            try:
                year_legislation = self.scrape_year(year, include_secondary)
                if year_legislation:
                    # Enrich with additional URLs
                    enriched_legislation = self.enrich_with_urls(year_legislation)
                    all_legislation.extend(enriched_legislation)
                    
                    # Save intermediate results
                    self.save_to_csv(all_legislation, f'uk_legislation_partial_{year}.csv')
                    
            except Exception as e:
                logger.error(f"Error scraping year {year}: {e}")
                continue
                
            # Longer pause between years
            time.sleep(3)
            
        return all_legislation
    
    def determine_act_type(self, legislation_type):
        """Determine if legislation is Local or General based on type"""
        if not legislation_type:
            return 'Unknown'
        
        legislation_type_lower = legislation_type.lower()
        
        if 'local' in legislation_type_lower:
            return 'Local'
        elif 'public general' in legislation_type_lower or 'public' in legislation_type_lower:
            return 'General'
        elif 'private' in legislation_type_lower:
            return 'Private'
        else:
            return 'General'  # Default assumption for most primary legislation
    
    def save_to_csv(self, legislation_list, filename='uk_primary_legislation.csv'):
        """Save legislation data to CSV"""
        logger.info(f"Saving {len(legislation_list)} items to {filename}")
        
        with open(filename, 'w', newline='', encoding='utf-8') as csvfile:
            fieldnames = [
                'year', 'num', 'name', 'page_url', 'plain_url', 'pdf_url', 
                'legislation_type', 'act_type', 'page_url_available', 
                'plain_url_available', 'pdf_url_available'
            ]
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            
            writer.writeheader()
            for item in legislation_list:
                act_type = self.determine_act_type(item.get('type', ''))
                writer.writerow({
                    'year': item.get('year', ''),
                    'num': item.get('num', ''),
                    'name': item.get('name', ''),
                    'page_url': item.get('page_url', ''),
                    'plain_url': item.get('plain_url', ''),
                    'pdf_url': item.get('pdf_url', ''),
                    'legislation_type': item.get('type', ''),
                    'act_type': act_type,
                    'page_url_available': item.get('page_url_available', False),
                    'plain_url_available': item.get('plain_url_available', False),
                    'pdf_url_available': item.get('pdf_url_available', False)
                })
        
        logger.info(f"Successfully saved to {filename}")
        
        # Log summary statistics
        total_items = len(legislation_list)
        available_pages = sum(1 for item in legislation_list if item.get('page_url_available', False))
        available_plain = sum(1 for item in legislation_list if item.get('plain_url_available', False))
        available_pdf = sum(1 for item in legislation_list if item.get('pdf_url_available', False))
        
        logger.info(f"Summary: {available_pages}/{total_items} pages available, "
                   f"{available_plain}/{total_items} plain URLs available, "
                   f"{available_pdf}/{total_items} PDF URLs available")

def main():
    parser = argparse.ArgumentParser(description='Scrape UK Primary Legislation data')
    parser.add_argument('--year', type=int, help='Specific year to scrape (e.g., 2020)')
    parser.add_argument('--start-year', type=int, default=1990, help='Start year for range scraping (default: 1990)')
    parser.add_argument('--end-year', type=int, default=2025, help='End year for range scraping (default: 2025)')
    parser.add_argument('--include-secondary', action='store_true', help='Include secondary legislation (default: primary only)')
    parser.add_argument('--test', action='store_true', help='Run test mode with limited items')
    parser.add_argument('--output', type=str, help='Output CSV filename')
    
    args = parser.parse_args()
    
    scraper = UKLegislationScraper()
    
    if args.year:
        # Scrape specific year
        if args.include_secondary:
            logger.info(f"Scraping primary and secondary legislation for year {args.year}")
        else:
            logger.info(f"Scraping primary legislation only for year {args.year}")
            
        legislation = scraper.scrape_year(args.year, args.include_secondary)
        
        if legislation:
            if args.test:
                # Test mode - only process first 5 items
                legislation = legislation[:5]
                logger.info(f"Test mode: processing only first {len(legislation)} items")
            
            enriched_legislation = scraper.enrich_with_urls(legislation)
            
            # Generate output filename
            if args.output:
                filename = args.output
            else:
                suffix = "_primary_secondary" if args.include_secondary else "_primary"
                filename = f'uk_legislation_{args.year}{suffix}.csv'
                
            scraper.save_to_csv(enriched_legislation, filename)
        else:
            logger.error(f"No legislation found for year {args.year}")
    
    else:
        # Scrape range of years
        start_year = args.start_year
        end_year = args.end_year
        
        if args.include_secondary:
            logger.info(f"Starting scrape of primary and secondary legislation from {start_year} to {end_year}")
        else:
            logger.info(f"Starting scrape of primary legislation only from {start_year} to {end_year}")
        
        if args.test:
            # Test mode - just scrape one year with limited items
            logger.info("Test mode: scraping only 2020 with first 5 items")
            test_legislation = scraper.scrape_year(2020, args.include_secondary)
            if test_legislation:
                enriched_test = scraper.enrich_with_urls(test_legislation[:5])
                filename = args.output if args.output else 'test_uk_legislation.csv'
                scraper.save_to_csv(enriched_test, filename)
        else:
            # Full range scrape
            all_legislation = scraper.scrape_all_years(start_year, end_year, args.include_secondary)
            
            if args.output:
                filename = args.output
            else:
                suffix = "_primary_secondary" if args.include_secondary else "_primary"
                filename = f'uk_legislation_complete{suffix}.csv'
                
            scraper.save_to_csv(all_legislation, filename)

if __name__ == "__main__":
    main()
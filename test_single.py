from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36")
    page.goto("https://www.glamira.fr/glamira-pendant-viktor.html?alloy=yellow-375", timeout=20000)
    print(page.title())
    content = page.content()
    print(len(content))
    browser.close()
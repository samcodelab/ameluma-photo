#!/usr/bin/env python3
"""Read-only release preflight. This checks artifacts, not Apple's approval or website availability."""
import argparse
import json
import ipaddress
import plistlib
import subprocess
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]

def valid_public_url(value):
    try:
        url = urlparse(value)
        host = url.hostname or ''
        try:
            if not ipaddress.ip_address(host).is_global:
                return False
        except ValueError:
            if '.' not in host:
                return False
        return url.scheme == 'https' and bool(host) and not url.username and not url.password and host not in {'localhost', 'example.com', 'example.org', 'example.net'} and not host.endswith(('.local', '.invalid', '.test', '.example', '.example.com', '.example.org', '.example.net'))
    except (ValueError, TypeError):
        return False

def read_plist(path):
    with path.open('rb') as file:
        return plistlib.load(file)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mac-app', type=Path)
    parser.add_argument('--ios-app', type=Path)
    parser.add_argument('--strict', action='store_true', help='Also require configured public URLs and signed distribution artifacts.')
    args = parser.parse_args()
    failures, blockers, checks = [], [], []
    def check(condition, message):
        (checks if condition else failures).append(message)
    entitlement = read_plist(ROOT / 'Apps/macOS/FramepebbleMac.entitlements')
    check(all(entitlement.get(key) is True for key in ['com.apple.security.app-sandbox', 'com.apple.security.files.user-selected.read-write', 'com.apple.security.files.bookmarks.app-scope']), 'Mac sandbox, selected-file access and persistent bookmark entitlements')
    check(entitlement.get('com.apple.security.network.client') is True and not any('network.server' in key or 'temporary-exception' in key for key in entitlement), 'User-initiated browser downloads only: client entitlement, no server or sandbox exceptions')
    distribution = read_plist(ROOT / 'Resources/Distribution.plist')
    for key in ['PrivacyPolicyURL', 'SupportURL']:
        if not valid_public_url(distribution.get(key, '')):
            blockers.append(f'{key}: supply and independently verify a working public HTTPS page')
    for platform, app in [('macOS', args.mac_app), ('iOS', args.ios_app)]:
        if not app:
            blockers.append(f'{platform}: no distribution artifact supplied')
            continue
        content = app / 'Contents' if platform == 'macOS' else app
        resources = content / 'Resources' if platform == 'macOS' else app
        try:
            info = read_plist(content / 'Info.plist')
            check(info.get('CFBundleIdentifier') == 'com.broadframestudio.framepebble', f'{platform}: shared Release bundle identity')
            check(info.get('CFBundleDisplayName') == 'Framepebble', f'{platform}: display name')
            check(bool(info.get('CFBundleShortVersionString')) and bool(info.get('CFBundleVersion')), f'{platform}: version and build number')
            check(not info.get('NSAppTransportSecurity', {}).get('NSAllowsArbitraryLoads', False), f'{platform}: no unrestricted transport exception')
            if platform == 'iOS':
                check(bool(info.get('NSPhotoLibraryAddUsageDescription')) and not info.get('NSPhotoLibraryUsageDescription'), 'iOS: add-only Photos purpose string')
                check(info.get('UIDeviceFamily') == [1, 2], 'iOS: iPhone and iPad support')
                check(float(info.get('MinimumOSVersion', '0')) >= 18, 'iOS: deployment target')
            else:
                check(float(info.get('LSMinimumSystemVersion', '0')) >= 15, 'macOS: deployment target')
                check(info.get('LSApplicationCategoryType') == 'public.app-category.photography', 'macOS: photography category')
            manifest = read_plist(resources / 'PrivacyInfo.xcprivacy')
            check(manifest.get('NSPrivacyTracking') is False and manifest.get('NSPrivacyCollectedDataTypes') == [], f'{platform}: no tracking/collected-data manifest declarations')
            reasons = {item['NSPrivacyAccessedAPIType']: set(item['NSPrivacyAccessedAPITypeReasons']) for item in manifest.get('NSPrivacyAccessedAPITypes', [])}
            check(reasons.get('NSPrivacyAccessedAPICategoryFileTimestamp') == {'C617.1', '3B52.1'}, f'{platform}: audited timestamp reasons')
            for filename in ['PrivacyPolicy.md', 'Help.md', 'Distribution.plist']:
                check((resources / filename).is_file(), f'{platform}: bundled {filename}')
            check(read_plist(resources / 'Distribution.plist') == distribution, f'{platform}: current policy/support configuration bundled')
            signature = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True)
            if signature.returncode != 0 or b'TeamIdentifier=not set' in signature.stderr or b'TeamIdentifier=' not in signature.stderr:
                blockers.append(f'{platform}: distribution signature/team not verified')
            elif platform == 'macOS':
                signed = plistlib.loads(signature.stdout)
                check(all(signed.get(key) is True for key in entitlement), 'macOS: sandbox/bookmark entitlements in actual signature')
        except (OSError, ValueError, plistlib.InvalidFileException, KeyError) as error:
            failures.append(f'{platform}: artifact inspection failed ({type(error).__name__})')
    print(json.dumps({'passed_checks': checks, 'failures': failures, 'submission_blockers': blockers, 'scope': 'Static preflight only; signed device testing, website availability, App Store Connect declarations and Apple review remain required.'}, indent=2))
    return 1 if failures or (args.strict and blockers) else 0

if __name__ == '__main__':
    raise SystemExit(main())

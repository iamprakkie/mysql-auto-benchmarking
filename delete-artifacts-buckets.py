import boto3

class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    OKORANGE = '\033[33m'
    OKRED = '\033[31m'
    OKWHITE = '\033[37m'
    OKWHITE2 = '\033[97m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

choice = input(f"{bcolors.OKRED}{bcolors.BOLD}This script will DELETE all bucket(s) that begins with 'autobench-' and ends with '-artifacts' in your AWS account.\nDo you want to proceed? (y/n) {bcolors.ENDC}")
if choice.lower() != 'y':
    print(f"{bcolors.OKRED}Exiting..{bcolors.ENDC}")
    exit()


# Get the list of all buckets
s3 = boto3.client("s3")
buckets = s3.list_buckets()
buckets.pop("ResponseMetadata")

# Iterate over the buckets
for bucket in buckets["Buckets"]:
    # Check if the bucket matches the name pattern
    if bucket["Name"].startswith('autobench-') and bucket["Name"].endswith('-artifacts'):
        print(f'{bcolors.HEADER}Working on bucket: {bucket["Name"]}{bcolors.ENDC}')

        try:
            response = s3.head_bucket(Bucket=bucket["Name"])
        except:
            print(f'{bcolors.FAIL}Error in accessing bucket. Skipping..{bcolors.ENDC}')
            print('-'*100)
            continue
        
        # Delete all objects in the bucket (including versions)
        versions = s3.list_object_versions(Bucket=bucket["Name"])
        for version in versions.get('Versions', []):
            s3.delete_object(Bucket=bucket["Name"], Key=version['Key'], VersionId=version['VersionId'])
            print(f'\t{bcolors.OKORANGE} Deleted object version(s) of {version["Key"]}{bcolors.ENDC}')

        # Delete all delete markers in the bucket (if any)
        for version in versions.get('DeleteMarkers', []):
            s3.delete_object(Bucket=bucket["Name"], Key=version['Key'], VersionId=version['VersionId'])
            print(f'\t{bcolors.OKORANGE} Deleted marker(s) of {version["Key"]}{bcolors.ENDC}')

        # Delete the bucket itself
        s3.delete_bucket(Bucket=bucket["Name"])

        print(f'{bcolors.OKGREEN} Bucket and all its contents have been deleted.{bcolors.ENDC}')
        print('-'*100)
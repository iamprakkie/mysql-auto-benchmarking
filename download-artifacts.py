import os
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

choice = input(f"{bcolors.OKWHITE2}{bcolors.BOLD}This script will download contents from all bucket(s) that begins with 'autobench-' and ends with '-artifacts' in your AWS account.\nDo you want to proceed? (y/n) {bcolors.ENDC}")
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
        print(f'{bcolors.HEADER}Downloading contents from bucket: {bucket["Name"]}{bcolors.ENDC}')

        try:
            response = s3.head_bucket(Bucket=bucket["Name"])
        except:
            print(f'{bcolors.FAIL}Error in accessing bucket. Skipping..{bcolors.ENDC}')
            print('-'*100)
            continue

        # create directory to download bucket contents
        os.makedirs(os.path.join(os.path.dirname(__file__), 'autobench_results', bucket["Name"]), exist_ok=True)

        objects = s3.list_objects_v2(Bucket=bucket["Name"])
        for object in objects["Contents"]:
            s3.download_file(bucket["Name"], object["Key"], f'autobench_results/{bucket["Name"]}/{object["Key"]}')
            print(f'{bcolors.OKGREEN} Downloaded file: {object["Key"]}{bcolors.ENDC}')
        
        print(f'{bcolors.OKGREEN} Downloaded contents from bucket: {bucket["Name"]}{bcolors.ENDC}')
        print('-'*100)

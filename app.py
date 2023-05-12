import os

from constructs import Construct
from aws_cdk.aws_s3_assets import Asset
from aws_cdk import (
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_s3 as s3,
    aws_s3_deployment as s3deploy,
    App, Stack, CfnOutput 
)

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
    
dirname = os.path.dirname(__file__)
mySQLAppName = str(os.getenv("BENCHMARK_NAME", "mysqlautobenchmarking"))
region = str(os.getenv("BENCHMARK_REGION",  "us-west-2"))
instType = str(os.getenv("MYSQL_INST_TYPE", "t3.medium"))
volSize = int(os.getenv("MYSQL_VOL_SIZE", 50))
volIOPS = int(os.getenv("MYSQL_VOL_IOPS", 150))
inputVolType = str(os.getenv("MYSQL_VOL_TYPE", "gp3"))
autobenchConf = str(os.getenv("MYSQL_AUTOBENCH_CONF", "fine-tuned-sysbench-autobench.conf"))
envName = str(os.getenv("BENCHMARK_ENV_NAME", "MySQLAutoBenchmarking"))

if inputVolType.lower() == 'gp2':
    volType = ec2.EbsDeviceVolumeType.GP2
elif inputVolType.lower() == 'gp3':
    volType = ec2.EbsDeviceVolumeType.GP3
elif inputVolType.lower() == 'io1':
    volType = ec2.EbsDeviceVolumeType.IO1
elif inputVolType.lower() == 'io2':
    volType = ec2.EbsDeviceVolumeType.IO2
else:
    print(f"{bcolors.WARNING}Unknown volume type found in env MYSQL_VOL_TYPE. Defaulting to GP3.{bcolors.ENDC}")
    volType = ec2.EbsDeviceVolumeType.GP3

class EC2InstanceStack(Stack):

    def __init__(self, scope: Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        # VPC
        vpc = ec2.Vpc(self, "VPC",
            enable_dns_hostnames = True,
            enable_dns_support = True,
            subnet_configuration=[ec2.SubnetConfiguration(name="public",subnet_type=ec2.SubnetType.PUBLIC,cidr_mask = 24)]
            )
        
        # create AZ lookup for subnet IDs
        publicSubnets = vpc.select_subnets(subnet_group_name="public")
        az_lookup = {}
        for publicSubnet in publicSubnets.subnets:
            az_lookup[publicSubnet.subnet_id] = publicSubnet.availability_zone

        #get subnet ID           
        publicSubnetId = vpc.select_subnets(subnet_group_name="public").subnet_ids[0]

        # Checking for supported architecture
        if ec2.InstanceType(instType).architecture != ec2.InstanceArchitecture.X86_64:
            print(f"{bcolors.FAIL}Unsupported architecture: {ec2.InstanceType(instType).architecture} of instance type {instType} in environment {envName}. Exiting..{bcolors.ENDC}")
            os.sys.exit(1)
            
        amzn_linux = ec2.MachineImage.latest_amazon_linux2(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            cpu_type=ec2.AmazonLinuxCpuType.X86_64,
            )       
            
        # Instance Role and SSM Managed Policy for MySQL instance
        cfnArn = "arn:aws:cloudformation:" + region + ":" + self.account + ":stack/" + mySQLAppName + "*"

        mySQLInstRole = iam.Role(self, "MySQLInstanceSSM", assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"))
        mySQLInstRole.add_managed_policy(iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"))
        mySQLInstRole.attach_inline_policy(
            iam.Policy(self, 'mySQLInstCfnPolicy',
                    statements = [
                    iam.PolicyStatement(
                    effect = iam.Effect.ALLOW,
                    actions = ['cloudformation:DescribeStacks'],
                    resources = [cfnArn]
                    )
                ]))
        mySQLInstRole.attach_inline_policy(
            iam.Policy(self, 'mySQLInstEc2Policy',
                    statements = [
                    iam.PolicyStatement(
                    effect = iam.Effect.ALLOW,
                    actions = ['ec2:DescribeInstances'],
                    resources = ["*"],
                    conditions = {
                        "ForAnyValue:StringEquals": {"aws:Ec2InstanceSourceVPC": vpc.vpc_id}
                    }
                    )
                ]))
        mySQLInstRole.attach_inline_policy(
            iam.Policy(self, 'mySQLInstLogsPolicy',
                    statements = [
                    iam.PolicyStatement(
                    effect = iam.Effect.ALLOW,
                    actions = ['logs:CreateLogGroup', 'logs:CreateLogStream', 'logs:PutLogEvents'],
                    resources = ["arn:aws:logs:" + region + ":" + self.account + ":log-group:*"]
                    )
                ]))

        # Instance Role and SSM Managed Policy for DBT2 instance
        dbt2InstRole = iam.Role(self, "DBT2InstanceSSM", assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"))
        dbt2InstRole.add_managed_policy(iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"))
        dbt2InstRole.attach_inline_policy(
            iam.Policy(self, 'dbt2InstCfnPolicy',
                    statements = [
                    iam.PolicyStatement(
                    effect = iam.Effect.ALLOW,
                    actions = ['cloudformation:DescribeStacks'],
                    resources = [cfnArn]
                )]))
        dbt2InstRole.attach_inline_policy(
            iam.Policy(self, 'dbt2InstEc2Policy',
                    statements = [
                    iam.PolicyStatement(
                    effect = iam.Effect.ALLOW,
                    actions = ['ec2:DescribeInstances'],
                    resources = ["*"],
                    conditions = {
                        "ForAnyValue:StringEquals": {"aws:Ec2InstanceSourceVPC": vpc.vpc_id}
                    }
                    )
                ]))
        dbt2InstRole.attach_inline_policy(
            iam.Policy(self, 'dbt2InstLogsPolicy',
                    statements = [
                    iam.PolicyStatement(
                    effect = iam.Effect.ALLOW,
                    actions = ['logs:CreateLogGroup', 'logs:CreateLogStream', 'logs:PutLogEvents'],
                    resources = ["arn:aws:logs:" + region + ":" + self.account + ":log-group:*"]
                    )
                ]))        

        #Security Group for DBT2 instance
        sg_dbt2 = ec2.SecurityGroup(
            self,
            id="dbt2-sg",
            vpc=vpc,
            allow_all_outbound=True,
            description="Security group of DBT2 instance",
            security_group_name = "dbt2-sg"
        )
        
        #Security Group for mySQL instance
        sg_mysql = ec2.SecurityGroup(
            self,
            id="mysql-access-sg",
            vpc=vpc,
            allow_all_outbound=True,
            description="Allow access to 3316 only from security group of DBT2 instance",
            security_group_name = "mysql-access-sg"
        )

        sg_mysql.add_ingress_rule(
            # peer=ec2.Peer.ipv4(vpc.vpc_cidr_block),
            peer=sg_dbt2,
            connection=ec2.Port.tcp(3316),
            description="MySQL access"
        )

        sg_mysql.add_ingress_rule(
            peer=sg_dbt2,
            connection=ec2.Port.tcp(22),
            description="SSH access"
        )        

        kp_mysql = ec2.CfnKeyPair(self, "MySQLCfnKeyPair", key_name='MySQLCfnKeyPair'+mySQLAppName)

        # mySQL Instance
        mySQLInstance = ec2.Instance(self, "MySQLInstance",
            instance_type=ec2.InstanceType(instance_type_identifier=instType),
            machine_image=amzn_linux,
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnets=[ec2.Subnet.from_subnet_attributes(self,"mySQLPublicSubnet",subnet_id=publicSubnetId,availability_zone=az_lookup[publicSubnetId])]),
            security_group=sg_mysql,
            key_name=kp_mysql.key_name,
            block_devices=[
                ec2.BlockDevice(device_name="/dev/xvda",volume=ec2.BlockDeviceVolume.ebs(100,delete_on_termination=True,volume_type=ec2.EbsDeviceVolumeType.GP3)),
                # ec2.BlockDevice(device_name="/dev/sda1",volume=ec2.BlockDeviceVolume.ebs(volSize,delete_on_termination=True,volume_type=volType))
            ],
            role = mySQLInstRole
            )
        
        if volType == ec2.EbsDeviceVolumeType.GP2:
            mySQLInstance.instance.add_property_override("BlockDeviceMappings", [
                {
                    "DeviceName": "/dev/sda1",
                    "Ebs": {
                        "VolumeSize": volSize,
                        "VolumeType": volType,
                        "DeleteOnTermination": "true"
                    }
                }
            ])
        else:
            mySQLInstance.instance.add_property_override("BlockDeviceMappings", [
                {
                    "DeviceName": "/dev/sda1",
                    "Ebs": {
                        "VolumeSize": volSize,
                        "VolumeType": volType,
                        "Iops": volIOPS,
                        "DeleteOnTermination": "true"
                    }
                }
            ])

        # Script in S3 as Asset
        asset = Asset(self, "mySQLAsset", path=os.path.join(dirname, "user-data-mysql-instance.sh"))
        local_path = mySQLInstance.user_data.add_s3_download_command(
            bucket=asset.bucket,
            bucket_key=asset.s3_object_key
        )

        # Userdata executes script from S3
        mySQLInstance.user_data.add_execute_file_command(
            file_path=local_path
            )
        asset.grant_read(mySQLInstance.role)        

        # DBT2 Instance
        dbt2Instance = ec2.Instance(self, "DBT2Instance",
            instance_type=ec2.InstanceType(instance_type_identifier=instType),
            machine_image=amzn_linux,
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnets=[ec2.Subnet.from_subnet_attributes(self,"dbt2PublicSubnet",subnet_id=publicSubnetId,availability_zone=az_lookup[publicSubnetId])]),
            security_group=sg_dbt2,
            block_devices=[
                ec2.BlockDevice(device_name="/dev/xvda",volume=ec2.BlockDeviceVolume.ebs(100,delete_on_termination=True,volume_type=ec2.EbsDeviceVolumeType.GP3)),
                # ec2.BlockDevice(device_name="/dev/sda1",volume=ec2.BlockDeviceVolume.ebs(100,delete_on_termination=True,volume_type=ec2.EbsDeviceVolumeType.GP3))
            ],
            role = dbt2InstRole
            )
        
        # Script in S3 as Asset
        asset = Asset(self, "dbt2Asset", path=os.path.join(dirname, "user-data-dbt2-instance.sh"))
        local_path = dbt2Instance.user_data.add_s3_download_command(
            bucket=asset.bucket,
            bucket_key=asset.s3_object_key
        )

        # Userdata executes script from S3
        dbt2Instance.user_data.add_execute_file_command(
            file_path=local_path
            )
        asset.grant_read(dbt2Instance.role)

        # Create S3 bucket to share artifacts
        s3_bucket = s3.Bucket(self, 'S3Bucket'+mySQLAppName, bucket_name=mySQLAppName+'-artifacts', versioned=True)
        s3_bucket.grant_read_write(mySQLInstance.role)
        s3_bucket.grant_read_write(dbt2Instance.role)

        env_var_filename = envName.replace(' ', "-") + '.env_vars'
        env_var_filename = env_var_filename.lower()
        autobench_conf_filename = envName.replace(' ', "-")+'-'+autobenchConf
        autobench_conf_filename = autobench_conf_filename.lower()
        
        s3deploy.BucketDeployment(self, 'S3BucketDeployment'+mySQLAppName,
            sources=[s3deploy.Source.asset(os.path.join(dirname, 'env_files'))],
            exclude=['**'],
            include=[env_var_filename,autobench_conf_filename],
            destination_bucket=s3_bucket,
            access_control=s3.BucketAccessControl.PRIVATE,
        )        

        #Cloudformation Outputs
        CfnOutput(self, 'vpcId', value=vpc.vpc_id, export_name='ExportedVpcId'+mySQLAppName)
        CfnOutput(self, "mySQLInstId", value=mySQLInstance.instance_id, export_name='ExportedMySQLInstId'+mySQLAppName)
        CfnOutput(self, "mySQLPrivIP", value=mySQLInstance.instance_private_ip, export_name='ExportedMySQLPrivIP'+mySQLAppName)
        CfnOutput(self, "dbt2InstId", value=dbt2Instance.instance_id, export_name='ExportedDBT2InstId'+mySQLAppName)
        CfnOutput(self, "dbt2PrivIP", value=dbt2Instance.instance_private_ip, export_name='ExportedDBT2PrivIP'+mySQLAppName)
        CfnOutput(self, "instArch", value=ec2.InstanceType(instType).architecture.value, export_name='ExportedInstArch'+mySQLAppName)
        CfnOutput(self, "s3BucketName", value=s3_bucket.bucket_name, export_name='ExportedS3BucketName'+mySQLAppName)
        CfnOutput(self,"mysqlRegion",value=region, export_name='ExportedMySQLRegion'+mySQLAppName)
        CfnOutput(self,"keyPairId", value=kp_mysql.attr_key_pair_id, export_name='ExportedKeyPairId'+mySQLAppName)
        
app = App()
EC2InstanceStack(app, mySQLAppName)
app.synth()

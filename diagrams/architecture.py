"""Architecture diagram — generated with the `diagrams` library.

Run: pip install diagrams && python diagrams/architecture.py
Produces: diagrams/clarity_platform_architecture.png
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import Lambda
from diagrams.aws.database import Dynamodb
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import APIGateway
from diagrams.aws.security import WAF, IAMRole
from diagrams.aws.compute import ECR
from diagrams.aws.storage import S3
from diagrams.onprem.client import Users

graph_attr = {
    "fontsize": "14",
    "bgcolor": "white",
    "pad": "0.5",
}

with Diagram(
    "Clarity Platform — Securities Scores API",
    filename="diagrams/clarity_platform_architecture",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
    outformat="png",
):
    clients = Users("Third-party\nClients")

    with Cluster("AWS Cloud"):
        waf = WAF("WAF v2\n(Rate Limit +\nManaged Rules)")

        with Cluster("API Layer"):
            apigw = APIGateway("API Gateway REST\n(Cache 0.5 GB / 300 s)")

        with Cluster("Compute"):
            ecr = ECR("ECR\n(Scan on Push)")
            lambda_fn = Lambda("Lambda\n(FastAPI + Mangum)")
            iam_role = IAMRole("Execution Role\n(Least Privilege)")

        with Cluster("Data"):
            ddb_securities = Dynamodb("Securities\n(Single Table)")

        monitoring = Cloudwatch("CloudWatch\n(Logs + Metrics)")

        with Cluster("Terraform State"):
            state_bucket = S3("S3\n(Remote State)")
            state_lock = Dynamodb("DynamoDB\n(State Lock)")

    # Flow
    clients >> Edge(label="HTTPS") >> waf >> apigw
    apigw >> Edge(label="Lambda Proxy") >> lambda_fn
    apigw >> Edge(style="dashed", label="access logs") >> monitoring
    ecr >> Edge(style="dashed", label="image") >> lambda_fn
    lambda_fn >> Edge(style="dashed", label="assumes") >> iam_role
    lambda_fn >> ddb_securities
    lambda_fn >> Edge(style="dashed", label="logs") >> monitoring
    state_bucket - Edge(style="dotted") - state_lock

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
        waf = WAF("WAF v2\n(Rate Limiting)")

        with Cluster("API Layer"):
            apigw = APIGateway("API Gateway\n(REST + Cache)")

        with Cluster("Compute"):
            ecr = ECR("ECR\n(Container Registry)")
            lambda_fn = Lambda("Lambda\n(FastAPI + Mangum)")
            iam_role = IAMRole("Execution Role\n(Least Privilege)")

        with Cluster("Data"):
            ddb_securities = Dynamodb("Securities\n(Single Table)")

        monitoring = Cloudwatch("CloudWatch\n(Logs + Alarms)")

    # Flow
    clients >> Edge(label="HTTPS") >> waf >> apigw
    apigw >> Edge(label="Lambda Proxy") >> lambda_fn
    ecr >> Edge(style="dashed", label="image") >> lambda_fn
    iam_role >> Edge(style="dashed", label="assumes") >> lambda_fn
    lambda_fn >> ddb_securities
    lambda_fn >> Edge(style="dashed") >> monitoring

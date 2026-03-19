Senior Platform Engineer Challenge

Context
We need to compute and serve refined scores for financial securities that will be consumed by third
parties worldwide. The tech team is building a set of services that ingest raw data, compute scores,
cache them, and expose them through a public API.
Your mission
Design and implement a working system in the AWS account we provide.
Design, deploy, and operate a public REST API in the AWS account provided.
The API must expose exactly these endpoints to third parties:
● GET /securities → returns a list of security IDs
● GET /securities/{security_id}/scores → returns score details for that security ID
You do not need to implement real business logic. You may use mocked/static data, but the service must
behave correctly.
API behavior requirements
● Responses must be JSON.
● GET /securities/{security_id}/scores must return:
○ A valid response for at least one known ID
○ 404 for unknown IDs
● Service must be reachable publicly over HTTPS.
1) Infrastructure diagram
Provide a diagram describing the infrastructure you designed, including all components you find relevant.
2) Running deployment in AWS
You must deploy both:
● The infrastructure
● The API service
All changes must be made in the AWS account provided using IaC and a private GitLab/GitHub
repository.
# ScreenMind — AWS Activate application preparation

Status: draft, not submitted. No AWS account, credit award, partner affiliation, domain registration, legal entity, or live deployment is claimed. Confirm all founder and company details before submitting.

## Product description
ScreenMind is an early-stage, privacy-first personal knowledge product for iOS. It turns screenshot collections into searchable information, project timelines, and source-linked rediscovery. The local-first architecture makes OCR, basic organization and retrieval available without a cloud account. We plan to add optional advanced AI through Amazon Bedrock, with explicit consent and source-level controls.

## Verified development evidence
- Personal iOS IPA built successfully: https://github.com/DavidPatlas-AI/screenmind-ios/actions/runs/45799938492
- 35 unit tests and 11 simulator UI tests passed in this build.
- Synthetic retrieval fixture: 12 of 12 expected top-ranked sources at 100, 200, 3,000 and 10,000 records. This is not real-world accuracy or phone performance.
- Physical-device validation and beta testing remain pending.
- Website source: startup-site/index.html; publish it at a real domain and configure a matching business email before applying.

## Proposed AWS use
- Bedrock: compare multilingual embeddings, evaluate text/image understanding, and generate source-grounded outputs. Benchmark Hebrew and mixed-language material before choosing a model.
- API Gateway and Lambda: authenticated request routing, quotas, validation and rate limits.
- DynamoDB: minimal account and job metadata, without raw screenshot contents by default.
- S3 and KMS: optional encrypted backup, only after consent, restore validation and data retention review.
- CloudWatch: operational metrics without logging prompts or private content.
- AWS Budgets: threshold alerts and explicit application-side limits; alerts alone do not cap charges.
No resources have been provisioned.

## Proposed use of $10,000, subject to actual eligible credit offer
Model evaluations and inference $3,500; OCR/multimodal experiments $2,000; multilingual retrieval $1,500; backup/restore $1,000; API, security and monitoring $1,000; testing and reserve $1,000. Planning allocation, not an AWS price quote. Spend only where justified. Confirm which Bedrock models/services qualify under the actual award.

## Applicant facts to confirm
- Founder name, company name and business/legal registration status
- Actual founding date, funding stage, latest funding round if applicable
- Business domain and matching email
- Existing AWS account and Activate award history
- Genuine Activate Provider affiliation, exact eligible credit package and Org ID if applicable
- Data residency, privacy notice and pilot consent

## Path to apply
AWS direct Founders: starts at $1,000; selected participants may qualify for up to $5,000. Portfolio: requires real provider affiliation and an Org ID; award varies. Verify eligibility, website and paid AWS plan before submitting. Never invent traction or affiliation.
Official sources:
https://aws.amazon.com/startups/credits/
https://aws.amazon.com/aws-startups/learn/applying-for-aws-activate-credits-a-step-by-step-guide/

## Potential Israeli route
peax cloud Founders Club advertises credit packages from $10k to $25k. Verify whether an independent early-stage founder qualifies, whether registration or a paid relationship is required, whether credits cover the intended Bedrock models, and whether provider affiliation/Org ID is offered. This is an advertised offer, not an awarded credit.
https://midlink.co.il/the-founders-club/

## Outreach draft (not sent)
Subject: ScreenMind — AWS startup credits and Bedrock pilot

Hello,
I am developing ScreenMind, an early-stage privacy-first iOS personal knowledge product that organizes screenshots, helps users retrieve information across languages, and reconnects related project sources. We have a successful iOS build and simulator tests; physical-device validation and beta testing are next.

We are evaluating Amazon Bedrock for multilingual retrieval and source-grounded AI. I would like to understand whether our project may qualify for your startup credit packages, particularly around $10,000. Could you clarify the eligibility requirements, company registration and funding requirements, any fees or commitments, and whether the credits cover our intended Bedrock workload?

Thank you.

## Publication checklist
Host the static startup-site directory with HTTPS. Test mobile navigation, the sample search and accessibility. Add a real contact method and actual privacy/contact details once confirmed. No fake registration form, investor logos, testimonials or usage statistics. Keep prototype and planned features clearly separate. Do not publicize private screenshots or repository content without review.

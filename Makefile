export AWS_DEFAULT_REGION=$(shell jq -r '.region' infrastructurerc.json)
export NAME=$(shell jq -r '.name' infrastructurerc.json)
export ORG=$(shell jq -r '.org' infrastructurerc.json)
export AWS_CICD_STACK_NAME=$(shell echo "${ORG}-cicd-${NAME}")
export AWS_PROFILE=cicd_aws_sam_ts

InvokeExampleFunction:
	node events/generate-api-gateway-event.js
	npm run build
	export AWS_PROFILE=default && \
	sam local invoke \
		--event events/APIGatewayProxyEvent.json \
		--template-file infrastructure.yml \
		--env-vars .env.json \
		'ExampleFunction'

build-deploy-cicd:
	make build
	AWS_ROLE_ARN=$$(aws --profile $$AWS_PROFILE \
		cloudformation describe-stacks --stack-name $$AWS_CICD_STACK_NAME \
		--query 'Stacks[0].Outputs[?OutputKey==`CICDRoleARN`].OutputValue' \
		--output text) && \
	ASSUME_ROLE=$$(aws --profile $$AWS_PROFILE --output json \
		sts assume-role --role-arn $$AWS_ROLE_ARN --role-session-name cicd-access \
		--query "Credentials") && \
	export AWS_ACCESS_KEY_ID=$$(echo $$ASSUME_ROLE | jq -r '.AccessKeyId') && \
	export AWS_SECRET_ACCESS_KEY=$$(echo $$ASSUME_ROLE | jq -r '.SecretAccessKey') && \
	export AWS_SESSION_TOKEN=$$(echo $$ASSUME_ROLE | jq -r '.SessionToken') && \
	sam deploy \
		--config-env dev \
		--stack-name "$${ORG}-dev-$${NAME}" \
		--s3-bucket "$${ORG}-cicd-$${NAME}" \
		--s3-prefix "dev" \
		--capabilities CAPABILITY_IAM \
		--no-fail-on-empty-changeset

update-all-npm:
	npx npm-check --update-all
	cd cicd-authorisation && npx npm-check --update-all

test-watch:
	npm run test:watch
test:
	npm run test
cicd-authorisation-test: cicd-authorisation/node_modules
	cd cicd-authorisation &&  npm run test

prettier:
	npm run prettier
prettier-fix:
	npm run prettier:fix

lint:
	yarn lint
lint-fix:
	yarn lint:fix

build-npm: node_modules
	npm run build
build-sam:
	sam build --template infrastructure.yml
build:
	make build-npm
	make build-sam

cicd-authorisation/node_modules:
	cd cicd-authorisation && npm install

node_modules:
	npm ci

check: test prettier lint cicd-authorisation-test

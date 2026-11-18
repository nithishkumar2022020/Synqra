// AWS Amplify Configuration for Synqra
// Generated manual configuration targeting AWS Cognito User Pool in ap-southeast-2

const amplifyconfig = '''{
  "UserAgent": "aws-amplify-cli/2.0",
  "Version": "1.0",
  "auth": {
    "plugins": {
      "awsCognitoAuthPlugin": {
        "UserAgent": "aws-amplify-cli/0.1.0",
        "Version": "0.1.0",
        "CognitoUserPool": {
          "Default": {
            "PoolId": "ap-southeast-2_cR0iLu56D",
            "AppClientId": "4p3oehrll2pd9p1ann0gvubp1c",
            "Region": "ap-southeast-2"
          }
        },
        "Auth": {
          "Default": {
            "authenticationFlowType": "USER_SRP_AUTH"
          }
        }
      }
    }
  }
}''';

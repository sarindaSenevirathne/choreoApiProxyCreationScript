import ballerina/graphql;
import ballerina/http;
import ballerina/io;
import ballerina/mime;

configurable string projectID = ?;
configurable string organizationID = ?;
configurable string orgIntID = ?;
configurable string organizationHandle = ?;
configurable string projectHandle = ?;
configurable string token = ?;

public function main() returns error? {

    do {

        stream<string[], io:Error?> csvStream = check io:fileReadCsvAsStream("apiInformation.csv");

        // Iterates through the stream and prints the content.
        check csvStream.forEach(function(string[] apiInfo) {

            string apiName = apiInfo[0].trim();
            string apiVersion = apiInfo[1].trim();
            string apiContext = apiInfo[2].trim();
            string apiDescription = apiInfo[3].trim();
            string apiProductionEndpoint = apiInfo[4].trim();
            string apiSandboxEndpoint = apiInfo[5].trim();
            string apiSpecFileName = apiInfo[6].trim();

            string|error apiID = importOpenAPISpecification(apiName, apiVersion, apiContext, apiDescription, apiProductionEndpoint, apiSandboxEndpoint, apiSpecFileName);

            if apiID is error {
                io:println(apiID);
            } else {
               string response = createComponent(apiID, apiName, apiVersion);
               io:println(response);
            }

        });

    } on fail error e {

        io:println("Error occurred while processing: ", e);

    }

}

function importOpenAPISpecification(string apiName, string apiVersion, string apiContext, string apiDescription, string apiProductionEndpoint, string apiSandboxEndpoint, string apiSpecFileName) returns string|error {

    do {

        http:Client httpEp = check new (url = string `https://sts.choreo.dev/api/am/publisher/v2/apis/import-openapi?organizationId=${organizationID}&importScopes=false`, config = {
            auth: {
                token: token
            }
        });

        json AdditonalProperties = {
            "name": apiName,
            "version": apiVersion,
            "context": string `${organizationID}/${projectHandle}/${apiContext}`,
            "description": apiDescription,
            "policies": [
                "Bronze"
            ],
            "visibility": "PRIVATE",
            "scopePrefix": string `urn:${organizationHandle}:${apiName}:`,
            "endpointConfig": {
                "endpoint_type": "http",
                "production_endpoints": {
                    "url": apiProductionEndpoint
                },
                "sandbox_endpoints": {
                    "url": apiSandboxEndpoint
                }
            },
            "additionalProperties": [
                {
                    "name": "projectId",
                    "value": projectID,
                    "display": true
                },
                {
                    "name": "accessibility",
                    "value": "external",
                    "display": true
                }
            ],
            "advertiseInfo": {
                "advertised": false,
                "apiExternalProductionEndpoint": apiProductionEndpoint
            }
        };

        mime:Entity additionalProperties = new;
        mime:ContentDisposition additionalPropertiesContentDisposition = new;
        additionalPropertiesContentDisposition.name = "additionalProperties";
        additionalPropertiesContentDisposition.disposition = "form-data";
        additionalProperties.setContentDisposition(additionalPropertiesContentDisposition);
        additionalProperties.setJson(AdditonalProperties);

        //Create an `swagger` body part as a file upload.
        mime:Entity file = new;
        mime:ContentDisposition fileContentDisposition = new;
        fileContentDisposition.name = "file";
        fileContentDisposition.disposition = "form-data";
        fileContentDisposition.fileName = apiSpecFileName;
        file.setContentDisposition(fileContentDisposition);

        // This file path is relative to where Ballerina is running.
        // If your file is located outside,
        // give the absolute file path instead.
        file.setFileAsEntityBody(string `/home/sarindas/Documents/POC/API-Creation-Script/createAPIs/specFiles/${apiSpecFileName}`, contentType = mime:TEXT_PLAIN);

        // Create an array to hold all the body parts.
        mime:Entity[] bodyParts = [file, additionalProperties];

        http:Request request = new;

        // Set the body parts to the request.
        // Here the content-type is set as multipart form data.
        // This also works with any other multipart media type.
        // E.g., `multipart/mixed`, `multipart/related` etc.
        // You need to pass the content type that suits your requirement.
        request.setBodyParts(bodyParts, contentType = mime:MULTIPART_FORM_DATA);

        http:Response returnResponse = check httpEp->/.post(request);

        if returnResponse.statusCode == 201 {
            json response = check returnResponse.getJsonPayload();
            string apiID = check response.id;
            return apiID;
        } else {
            return error(string `Status code is not 201. Status code is ${returnResponse.statusCode}`);
        }

    } on fail error e {
        return error(string `Error occurred while importing the API ${apiName} ${apiVersion}. Reaseon = ${e.toString()}`);
    }

}

function createComponent(string apiID, string apiName, string apiVersion) returns string {

    do {
        graphql:Client graphqlEp = check new (serviceUrl = "https://apis.choreo.dev/projects/1.0.0/graphql", clientConfig = {
            auth: {
                token: token
            }
        });

        string doc = string `mutation{ createComponent(
            component: {
                name: "${apiName}",
                orgId: ${orgIntID},
                orgHandler: "${organizationHandle}",
                displayName: "${apiName}",
                displayType: "proxy",
                projectId: "${projectID}",
                labels: "",
                version: "${apiVersion}",
                description: "",
                apiId: "${apiID}",
                ballerinaVersion: "swan-lake-alpha5",
                triggerChannels: "",
                triggerID: null,
                httpBase: true,
                sampleTemplate: "",
                accessibility: "external",        
                repositorySubPath: "",
                repositoryType: "",
                repositoryBranch: "",
                initializeAsBallerinaProject: false,
                enableCellDiagram: true,
                secretRef: "undefined"
            }){
                id, orgId, projectId, handler
            }}`;

        json response = check graphqlEp->execute(doc);
        io:println(response);

        return string `API(${apiName} ${apiVersion}) Creation successful. Respective API ID = ${apiID}`;

    } on fail error e {
        return string `API(${apiName} ${apiVersion}) Creation failed. Reason = ${e.toString()}`;
    }

}

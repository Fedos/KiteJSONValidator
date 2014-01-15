//
//  KiteJSONValidator.m
//  MCode
//
//  Created by Sam Duke on 15/12/2013.
//  Copyright (c) 2013 Airsource Ltd. All rights reserved.
//

#import "KiteJSONValidator.h"

@implementation KiteJSONValidator

//-(BOOL)validateJSONUnknown:(NSObject*)object withSchemaDict:(NSDictionary*)schema
//{
//    if (![self checkSchemaRef:schema]) {
//        return FALSE;
//    }
//    if (schema[@"required"]) {
//        if (![self checkRequired:schema forJSON:object]) {
//            return FALSE;
//        }
//    }
//    if (schema[@"type"]) {
//        
//    }
//    return TRUE;
//}

+(BOOL)propertyIsInteger:(id)property
{
    return [property isMemberOfClass:[NSNumber class]] &&
           [property isEqualToNumber:[NSNumber numberWithInteger:[property integerValue]]];
}

+(BOOL)propertyIsPositiveInteger:(id)property
{
    return [KiteJSONValidator propertyIsInteger:property] &&
           [property longLongValue] >= 0;
}

-(BOOL)validateJSONDict:(NSDictionary*)json withSchemaDict:(NSDictionary*)schema
{
    //first validate the schema against the root schema then validate against the original
    NSString *rootSchemaPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"schema"
                                                                                ofType:@""];
    //TODO: error out if the path is nil
    NSData *rootSchemaData = [NSData dataWithContentsOfFile:rootSchemaPath];
    NSError *error = nil;
    NSDictionary * rootSchema = [NSJSONSerialization JSONObjectWithData:rootSchemaData
                                                    options:kNilOptions
                                                      error:&error];
    NSLog(@"Root Schema: %@", rootSchema);
    if (![self _validateJSONObject:schema withSchemaDict:[rootSchema mutableCopy]])
    {
        return FALSE; //error: invalid schema
    }
    else if (![self _validateJSONObject:json withSchemaDict:[schema mutableCopy]])
    {
        return FALSE;
    }
    else
    {
        return TRUE;
    }
}

-(BOOL)_validateJSONObject:(NSDictionary*)JSONDict withSchemaDict:(NSMutableDictionary*)schema
{
    //may be better to pull out the keys from the schema in order (so that additional properties comes after properties and patternProperties - these can be used to add schema for child properties etc). then in additionalProperties, check keys of the collections of child property schema for gaps. the whole properties part could be considered equivalent to "get the schema for each child, if there isnt a schema for each child then fail". do properties, then pattern properties, then additional properties, then check.
    //Could remove alot of checks for invalid schema by first checking the schema against the core schema. have a public entry point to check the schema, then dont check again. optimize for repeated references perhaps (a 'checked schema' array?)
    static NSArray * dictionaryKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dictionaryKeywords = @[@"maxProperties", @"minProperties", @"required", @"properties",/* @"patternProperties", @"additionalProperties",*/ @"dependencies"];
    });
    
    NSMutableDictionary * propertySchema = [NSMutableDictionary dictionaryWithSharedKeySet:[NSDictionary sharedKeySetForKeys:[JSONDict allKeys]]];
    for (NSString * keyword in dictionaryKeywords) {
        if (schema[keyword]) {
            if ([keyword isEqualToString:@"maxProperties"]) {
                if (![KiteJSONValidator propertyIsPositiveInteger:JSONDict[keyword]]) {
                    //The value of this keyword MUST be an integer. This integer MUST be greater than, or equal to, 0.
                    return FALSE; //invalid schema
                }
                NSInteger maxProperties = [JSONDict[keyword] integerValue];
                if ([[JSONDict allKeys] count] > maxProperties) {
                    //An object instance is valid against "maxProperties" if its number of properties is less than, or equal to, the value of this keyword.
                    return FALSE; //invalid JSON dict
                }
            } else if ([keyword isEqualToString:@"minProperties"]) {
                if (![KiteJSONValidator propertyIsPositiveInteger:JSONDict[keyword]]) {
                    //The value of this keyword MUST be an integer. This integer MUST be greater than, or equal to, 0.
                    return FALSE; //invalid schema
                }
                NSInteger minProperties = [JSONDict[keyword] integerValue];
                if ([[JSONDict allKeys] count] < minProperties) {
                    //An object instance is valid against "minProperties" if its number of properties is greater than, or equal to, the value of this keyword.
                    return FALSE; //invalid JSON dict
                }
            } else if ([keyword isEqualToString:@"required"]) {
                if (![self checkRequired:schema forJSON:JSONDict]) {
                    return FALSE;
                }
            } else if ([keyword isEqualToString:@"properties"]) {
                //If "additionalProperties" is absent, it may be considered present with an empty schema as a value.
                if (schema[@"additionalProperties"] == nil) {
                    schema[@"additionalProperties"] = [NSDictionary new]; //TODO: the 'defaults' in the root schema should actually fix this for us
                }
                //If either "properties" or "patternProperties" are absent, they can be considered present with an empty object as a value.
                if (schema[@"properties"] == nil) {
                    schema[@"properties"] = [NSDictionary new];
                }
                if (schema[@"patternProperties"] == nil) {
                    schema[@"patternProperties"] = [NSDictionary new];
                }

                //Successful validation of an object instance against these three keywords depends on the value of "additionalProperties":
                //    if its value is boolean true or a schema, validation succeeds;
                //    if its value is boolean false, the algorithm to determine validation success is described below.
                if (!schema[@"additionalProperties"]) { //value must be boolean false
                    
                    NSSet * p = [NSSet setWithArray:[schema[@"properties"] allKeys]];
                    NSArray * pp = [schema[@"patternProperties"] allKeys];
                    NSMutableSet * s = [NSMutableSet setWithArray:[JSONDict allKeys]];
                    //remove from "s" all elements of "p", if any;
                    [s minusSet:p];
                    //we loop the regexes so each is only created once
                    [pp enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                        NSString * regexString = obj;
                        //Each property name of this object SHOULD be a valid regular expression, according to the ECMA 262 regular expression dialect.
                        //NOTE: this regex uses ICU which has some differences to ECMA-262 (such as look-behind)
                        NSError * error;
                        //potentially inefficient as the regex object is recreated numerous times
                        NSRegularExpression * regex = [NSRegularExpression regularExpressionWithPattern:regexString options:0 error:&error];
                        if (error) {
                           return;
                        }
                        [s minusSet:[s objectsPassingTest:^BOOL(id obj, BOOL *stop) {
                           NSString * keyString = obj;
                           return [regex firstMatchInString:keyString options:0 range:NSMakeRange(0, keyString.length)];
                        }]];
                        if ([s count] == 0) {
                           *stop = YES;
                        }
                    }];
                    //Validation of the instance succeeds if, after these two steps, set "s" is empty.
                    if ([s count] > 0) {
                        return FALSE;
                    }
                }
            } else if ([keyword isEqualToString:@"patternProperties"]) {
            } else if ([keyword isEqualToString:@"additionalProperties"]) {
                if (JSONDict[keyword] != FALSE) {
                    //if its value is boolean true or a schema, validation succeeds;
                    continue;
                }
                //TODO: the properties validation needs to be mixed with schema selection for child validation. NOTE: "object member values may have to validate against more than one schema." - i.e. there may be multiple children schema to validate against (from properties and pattern properties)
                NSMutableArray * s = [[JSONDict allKeys] mutableCopy];
                if ([s count] == 0) {
                    continue; //nothing to test
                }
                NSArray * p;
                if (schema[@"properties"])
                {
                    if ([schema[@"properties"] isKindOfClass:[NSDictionary class]]) {
                        p = [schema[@"properties"] allKeys];
                        //TODO: Each value of this object MUST be an object, and each object MUST be a valid JSON Schema.
                    } else {
                        return FALSE; //invalid schema
                    }
                } else {
                    //If either "properties" or "patternProperties" are absent, they can be considered present with an empty object as a value.
                    p = [NSArray new];
                }
                NSArray * pp;
                if (schema[@"patternProperties"]) {
                    if ([schema[@"patternProperties"] isKindOfClass:[NSDictionary class]]) {
                        pp = [schema[@"patternProperties"] allKeys];
                        //TODO: Each property name of this object SHOULD be a valid regular expression, according to the ECMA 262 regular expression dialect. Each property value of this object MUST be an object, and each object MUST be a valid JSON Schema.
                    } else {
                        return FALSE; //invalid schema
                    }
                } else {
                    //If either "properties" or "patternProperties" are absent, they can be considered present with an empty object as a value.
                    pp = [NSArray new];
                }
                
                //Step 1. remove from "s" all elements of "p", if any;
                [s removeObjectsInArray:p];
                if ([s count] == 0) {
                    continue; //nothing left to test
                }
                
                //Step 2. for each regex in "pp", remove all elements of "s" which this regex matches.
                for (NSString * regexString in pp) {
                    NSError * regexError;
                    NSRegularExpression * regex = [NSRegularExpression regularExpressionWithPattern:regexString options:0 error:&regexError];
                    if (regexError) {
                        //Each property name of this object SHOULD be a valid regular expression
                        //This one is not, so we just continue and ignore it.
                        continue;
                    }
                    for (NSString * propertyString in s) {
                        if ([regex numberOfMatchesInString:propertyString options:0 range:NSMakeRange(0, propertyString.length)] > 0) {
                            [s removeObject:propertyString]; //slightly worrisome changing the array while looping it....
                        }
                    }
                    if ([s count] == 0 ) {
                        break;
                    }
                }
                
                //Validation of the instance succeeds if, after these two steps, set "s" is empty.
                if ([s count] > 0 ) {
                    return FALSE; //invalid JSON dict
                }
            } else if ([keyword isEqualToString:@"dependencies"]) {
                
            }
        }
    }
    
    for (NSString * propertyKey in [schema keyEnumerator]) {
        if ([propertyKey isEqualToString:@"maxProperties"]) {
            if (![KiteJSONValidator propertyIsPositiveInteger:JSONDict[propertyKey]]) {
                //The value of this keyword MUST be an integer. This integer MUST be greater than, or equal to, 0.
                return FALSE; //invalid schema
            }
            NSInteger maxProperties = [JSONDict[propertyKey] integerValue];
            if ([[JSONDict allKeys] count] > maxProperties) {
                //An object instance is valid against "maxProperties" if its number of properties is less than, or equal to, the value of this keyword.
                return FALSE; //invalid JSON dict
            }
        } else if ([propertyKey isEqualToString:@"minProperties"]) {
            if (![KiteJSONValidator propertyIsPositiveInteger:JSONDict[propertyKey]]) {
                //The value of this keyword MUST be an integer. This integer MUST be greater than, or equal to, 0.
                return FALSE; //invalid schema
            }
            NSInteger minProperties = [JSONDict[propertyKey] integerValue];
            if ([[JSONDict allKeys] count] < minProperties) {
                //An object instance is valid against "minProperties" if its number of properties is greater than, or equal to, the value of this keyword.
                return FALSE; //invalid JSON dict
            }
        } else if ([propertyKey isEqualToString:@"required"]) {
            if (![self checkRequired:schema forJSON:JSONDict]) {
                return FALSE;
            }
        } else if ([propertyKey isEqualToString:@"additionalProperties"]) {
            if (JSONDict[propertyKey] != FALSE) {
                //if its value is boolean true or a schema, validation succeeds;
                continue;
            }
            //TODO: the properties validation needs to be mixed with schema selection for child validation. NOTE: "object member values may have to validate against more than one schema." - i.e. there may be multiple children schema to validate against (from properties and pattern properties)
            NSMutableArray * s = [[JSONDict allKeys] mutableCopy];
            if ([s count] == 0) {
                continue; //nothing to test
            }
            NSArray * p;
            if (schema[@"properties"])
            {
                if ([schema[@"properties"] isKindOfClass:[NSDictionary class]]) {
                    p = [schema[@"properties"] allKeys];
                    //TODO: Each value of this object MUST be an object, and each object MUST be a valid JSON Schema.
                } else {
                    return FALSE; //invalid schema
                }
            } else {
                //If either "properties" or "patternProperties" are absent, they can be considered present with an empty object as a value.
                p = [NSArray new];
            }
            NSArray * pp;
            if (schema[@"patternProperties"]) {
                if ([schema[@"patternProperties"] isKindOfClass:[NSDictionary class]]) {
                    pp = [schema[@"patternProperties"] allKeys];
                    //TODO: Each property name of this object SHOULD be a valid regular expression, according to the ECMA 262 regular expression dialect. Each property value of this object MUST be an object, and each object MUST be a valid JSON Schema.
                } else {
                    return FALSE; //invalid schema
                }
            } else {
                //If either "properties" or "patternProperties" are absent, they can be considered present with an empty object as a value.
                pp = [NSArray new];
            }
            
            //Step 1. remove from "s" all elements of "p", if any;
            [s removeObjectsInArray:p];
            if ([s count] == 0) {
                continue; //nothing left to test
            }
            
            //Step 2. for each regex in "pp", remove all elements of "s" which this regex matches.
            for (NSString * regexString in pp) {
                NSError * regexError;
                NSRegularExpression * regex = [NSRegularExpression regularExpressionWithPattern:regexString options:0 error:&regexError];
                if (regexError) {
                    //Each property name of this object SHOULD be a valid regular expression
                    //This one is not, so we just continue and ignore it.
                    continue;
                }
                for (NSString * propertyString in s) {
                    if ([regex numberOfMatchesInString:propertyString options:0 range:NSMakeRange(0, propertyString.length)] > 0) {
                        [s removeObject:propertyString]; //slightly worrisome changing the array while looping it....
                    }
                }
                if ([s count] == 0 ) {
                    break;
                }
            }
            
            //Validation of the instance succeeds if, after these two steps, set "s" is empty.
            if ([s count] > 0 ) {
                return FALSE; //invalid JSON dict
            }
        } else if ([propertyKey isEqualToString:@"dependencies"]) {
            
        }
    }
    return TRUE;
}

-(BOOL)checkRequired:(NSDictionary*)schema forJSON:(NSDictionary*)json
{
    if (![schema[@"required"] isKindOfClass:[NSArray class]]) {
        //The value of this keyword MUST be an array.
        return FALSE; //invalid schema
    }
    NSArray * requiredArray = schema[@"required"];
    if (![requiredArray count] > 0) {
        //This array MUST have at least one element.
        return  FALSE; //invalid schema
    }
    if (!([[NSSet setWithArray: requiredArray] count] == [requiredArray count])) {
        //Elements of this array MUST be unique.
        return FALSE; // invalid schema
    }
    for (NSObject * requiredProp in requiredArray) {
        if (![requiredProp isKindOfClass:[NSString class]]) {
            //Elements of this array MUST be strings.
            return FALSE; // invalid schema
        }
        NSString * requiredPropStr = (NSString*)requiredProp;
        if (![json valueForKey:requiredPropStr]) {
            return FALSE; //required not present. invalid JSON dict.
        }
    }
    return TRUE;
}

-(BOOL)checkSchemaRef:(NSDictionary*)schema
{
    NSArray * validSchemaArray = @[
                                   @"http://json-schema.org/schema#",
                                   //JSON Schema written against the current version of the specification.
                                   //@"http://json-schema.org/hyper-schema#",
                                   //JSON Schema written against the current version of the specification.
                                   @"http://json-schema.org/draft-04/schema#",
                                   //JSON Schema written against this version.
                                   @"http://json-schema.org/draft-04/hyper-schema#",
                                   //JSON Schema hyperschema written against this version.
                                   //@"http://json-schema.org/draft-03/schema#",
                                   //JSON Schema written against JSON Schema, draft v3 [json‑schema‑03].
                                   //@"http://json-schema.org/draft-03/hyper-schema#"
                                   //JSON Schema hyperschema written against JSON Schema, draft v3 [json‑schema‑03].
                                   ];
    
    if ([validSchemaArray containsObject:schema[@"$schema"]]) {
        return TRUE;
    } else {
        return FALSE; //invalid schema - although technically including $schema is only RECOMMENDED
    }
}

@end

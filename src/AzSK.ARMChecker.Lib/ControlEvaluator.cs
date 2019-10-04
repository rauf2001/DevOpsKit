using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;
using AzSK.ARMChecker.Lib.Extensions;
using System.Collections;
using System.Text.RegularExpressions;

namespace AzSK.ARMChecker.Lib
{
    public class ControlEvaluator
    {
        private readonly JObject _template;
        private  readonly JObject _externalParameters;
        private  static JObject _externalParametersDict;
        private static JObject _armTemplate;

        public ControlEvaluator(JObject template, JObject externalParameters)
        {
            _template = template;
            _externalParameters = externalParameters;
            SetParametersList();
        }
        public void SetParametersList()
        {
            _externalParametersDict = _externalParameters;
            _armTemplate = _template;
        }
        public ControlResult Evaluate(ResourceControl control, JObject resource)
        {
            switch (control.MatchType)
            {
                case ControlMatchType.Null:
                    return ControlResult.NotSupported(resource);
                case ControlMatchType.Boolean:
                    return EvaluateBoolean(control, resource);
                case ControlMatchType.IntegerValue:
                    return EvaluateIntegerValue(control, resource);
                case ControlMatchType.ItemCount:
                    return EvaluateItemCount(control, resource);
                case ControlMatchType.ItemProperties:
                    return EvaluateItemProperties(control, resource);
                case ControlMatchType.SecureParam:
                    return EvaluateSecureParam(control, resource);
                case ControlMatchType.StringLength:
                    return ControlResult.NotSupported(resource);
                case ControlMatchType.StringWhitespace:
                    return EvaluateStringWhitespace(control, resource);
                case ControlMatchType.StringSingleToken:
                    return EvaluateStringSingleToken(control, resource);
                case ControlMatchType.StringMultiToken:
                    return EvaluateStringMultiToken(control, resource);
                case ControlMatchType.RegExpressionSingleToken:
                    return EvaluateRegExpressionSingleToken(control, resource);
                case ControlMatchType.RegExpressionMultiToken:
                    return ControlResult.NotSupported(resource);
                case ControlMatchType.VerifiableSingleToken:
                    return EvaluateVerifiableSingleToken(control, resource);
                case ControlMatchType.VerifiableMultiToken:
                    return ControlResult.NotSupported(resource);
                case ControlMatchType.Custom:
                    return ControlResult.NotSupported(resource);
                case ControlMatchType.NullableSingleToken:
                    return EvaluateNullableSingleToken(control, resource);
                case ControlMatchType.VersionSingleToken:
                    return EvaluateSingleVersionToken(control, resource);
                case ControlMatchType.BooleanVerify:
                    return EvaluateBooleanVerifystate(control, resource);
             default:
                    throw new ArgumentOutOfRangeException();
            }
        }

        private static ControlResult EvaluateBoolean(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out bool actual, out BooleanControlData match);
            result.ExpectedValue = "'" + match.Value.ToString() + "'";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            if (actual == match.Value)
            {
                result.VerificationResult = VerificationResult.Passed;
            }
            return result;
        }

        private static ControlResult EvaluateBooleanVerifystate(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out bool actual, out BooleanControlData match);
            result.ExpectedValue = "'" + match.Value.ToString() + "'";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            if (actual == match.Value)
            {
                result.VerificationResult = VerificationResult.Passed;
            }
            else
            {
                result.VerificationResult = VerificationResult.Verify;
            }
            return result;
        }

        private static ControlResult EvaluateIntegerValue(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out int actual, out IntegerValueControlData match);
            result.ExpectedValue = match.Type.ToString() + " " + match.Value.ToString();
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            switch (match.Type)
            {
                case ControlDataMatchType.GreaterThan:
                    if (actual > match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                case ControlDataMatchType.LesserThan:
                    if (actual < match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                case ControlDataMatchType.Equals:
                    if (actual == match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                default:
                    throw new ArgumentOutOfRangeException();
            }
            return result;
        }

        private static ControlResult EvaluateItemCount(ResourceControl control, JObject resource)
        {
            var result = ExtractMultiToken(control, resource, out IEnumerable<object> actual, out IntegerValueControlData match);
            result.ExpectedValue = "Count " + match.Type.ToString() + " " + match.Value.ToString();
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            var count = actual.Count();
            switch (match.Type)
            {
                case ControlDataMatchType.GreaterThan:
                    if (count > match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                case ControlDataMatchType.LesserThan:
                    if (count < match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                case ControlDataMatchType.Equals:
                    if (count == match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                case ControlDataMatchType.limit:
                    if ((count >= 0)  && (count<= match.Value)) result.VerificationResult = VerificationResult.Verify;
                    break;
                case ControlDataMatchType.All:
                    string temp=null;
                    foreach (var obj in actual)
                    {
                        temp= obj.ToString();
                        break;
                    }
                    if (count > match.Value && temp.Equals("*"))
                    {
                        result.VerificationResult = VerificationResult.Failed;
                    }
                    else
                    {
                        result.VerificationResult = VerificationResult.Verify;
                    }
                    break;
                default:
                    throw new ArgumentOutOfRangeException();
            }
            return result;
        }

        private static ControlResult EvaluateItemProperties(ResourceControl control, JObject resource)
        {
            var result = ExtractMultiToken(control, resource, out IEnumerable<object> actual, out CustomTokenControlData match);
            result.ExpectedValue = " '"+match.Key+" ':" + " '" + match.Value + "'";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            bool keyValueFound = false;
            foreach (JObject obj in actual)
            {
                var dictObject = obj.ToObject<Dictionary<string, string>>();
                if(dictObject.ContainsKey(match.Key) && dictObject[match.Key] == match.Value)
                {
                    keyValueFound = true;
                    break;
                }
            } 
            if(keyValueFound)
            {
                result.VerificationResult = VerificationResult.Passed;
            }
            else
            {
                result.VerificationResult = VerificationResult.Failed;
            }
            return result;
        }

        private static ControlResult EvaluateStringMultiToken(ResourceControl control, JObject resource)
        {
            var result = ExtractMultiToken(control, resource, out IEnumerable<object> actual, out StringMultiTokenControlData match);
            result.ExpectedValue = " '" + match.Type + " ':" + " [" + string.Join("", match.Value) + "]";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            if(actual == null)
            {
                return result;
            }
            var count = actual.Count();
            string[] currentValue = new string[count];
            int index = 0;
            foreach (var obj in actual)
            {
                currentValue[index++] = obj.ToString();
            }
            if(match.Type == ControlDataMatchType.Contains)
            {
                if (match.Value.Except(currentValue).Any())
                {
                    result.VerificationResult = VerificationResult.Failed;
                }
                else
                {
                    result.VerificationResult = VerificationResult.Passed;
                }
            }
            else if(match.Type == ControlDataMatchType.NotContains){
                if (match.Value.Except(currentValue).Any())
                {
                    result.VerificationResult = VerificationResult.Passed;
                }
                else
                {
                    result.VerificationResult = VerificationResult.Failed;
                }
            }else if(match.Type == ControlDataMatchType.Equals)
            {
                Array.Sort(match.Value);
                Array.Sort(currentValue);
                if (currentValue.SequenceEqual(match.Value))
                {
                    result.VerificationResult = VerificationResult.Passed;
                }
                else
                {
                    result.VerificationResult = VerificationResult.Failed;
                }
            }
            return result;
        }

        private static ControlResult EvaluateStringWhitespace(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out string actual, out BooleanControlData match);
            result.ExpectedValue = (match.Value) ? "Null string" : "Non-null string";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            if (string.IsNullOrWhiteSpace(actual) == match.Value)
            {
                result.VerificationResult = VerificationResult.Passed;
            }
            return result;
        }

        private static ControlResult EvaluateStringSingleToken(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out string actual, out StringSingleTokenControlData match);
            result.ExpectedValue = match.Type + " '" + match.Value + "'";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            if (match.Value.Equals(actual,
                match.IsCaseSensitive ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase))
            {
                if (match.Type == ControlDataMatchType.Allow)
                {
                    result.VerificationResult = VerificationResult.Passed;
                }

            }
            else
            {
                if (match.Type == ControlDataMatchType.NotAllow)
                {
                    result.VerificationResult = VerificationResult.Passed;
                }
                if (match.Type == ControlDataMatchType.StringNotMatched)
                {
                    result.VerificationResult = VerificationResult.Verify;
                }
            }
            return result;
        }
        private static ControlResult EvaluateRegExpressionSingleToken(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out string actual, out RegExpressionSingleTokenControlData match);
            result.ExpectedValue = match.Type + " '" + match.Pattern + "'";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            if(actual == null || match.Pattern == null)
            {
                return result;
            }
            Regex regex;
            if(match.IsCaseSensitive)
            {
                regex = new Regex(@match.Pattern);
            }
            else
            {
                regex = new Regex(@match.Pattern, RegexOptions.IgnoreCase);
            }
            Match matchPattern = regex.Match(actual);
            if(match.Type == ControlDataMatchType.Allow)
            {
                if(matchPattern.Success)
                {
                    result.VerificationResult = VerificationResult.Passed;
                }else
                {
                    result.VerificationResult = VerificationResult.Failed;
                }
            }else if(match.Type == ControlDataMatchType.NotAllow)
            {
                if (!matchPattern.Success)
                {
                    result.VerificationResult = VerificationResult.Passed;
                }
                else
                {
                    result.VerificationResult = VerificationResult.Failed;
                }
            }
            return result;
        }
        private static ControlResult EvaluateSingleVersionToken(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out string actual, out StringSingleTokenControlData match);
            result.ExpectedValue = match.Type + " '" + match.Value + "'";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            var actualVersion = new Version(actual);
            var requiredVersion = new Version(match.Value);
            switch (match.Type)
             {
                 case ControlDataMatchType.GreaterThan:
                     if (actualVersion >requiredVersion) result.VerificationResult = VerificationResult.Passed;
                     break;
                 case ControlDataMatchType.LesserThan:
                     if (actualVersion < requiredVersion) result.VerificationResult = VerificationResult.Passed;
                     break;
                 case ControlDataMatchType.Equals:
                     if (actualVersion == requiredVersion) result.VerificationResult = VerificationResult.Passed;
                     break;
                case ControlDataMatchType.GreaterThanOrEqual:
                    if (actualVersion >= requiredVersion) result.VerificationResult = VerificationResult.Passed;
                    break;
                case ControlDataMatchType.LesserThanOrEqual:
                    if (actualVersion <= requiredVersion) result.VerificationResult = VerificationResult.Passed;
                    break;
                default:
                     throw new ArgumentOutOfRangeException();
             }
            return result;
        }
        private static ControlResult EvaluateSecureParam(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out string actual, out BooleanControlData match,false);
            result.ExpectedValue = "Parameter type: SecureString";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            string parameterType = null;
            try
            {
                if (actual != null && actual.CheckIsParameter())
                {
                    var parameterKey = actual.GetParameterKey();
                    if (parameterKey != null)
                    {
                        JObject innerParameters = _armTemplate["parameters"].Value<JObject>();
                        parameterType = innerParameters.Properties().Where(p => p.Name == parameterKey).Select(p => p.Value["type"].Value<String>()).FirstOrDefault();
                    }
                }
                else
                {
                    // If property value is not a parameter, mark control status as Verify
                    result.VerificationResult = VerificationResult.Verify;
                }
            }
            catch(Exception)
            {
                 parameterType = null;
                // No need to block execution, mark control as fail
            }
            if(parameterType.IsNotNullOrWhiteSpace() && parameterType.Equals("SecureString", StringComparison.OrdinalIgnoreCase))
            {
               result.VerificationResult = VerificationResult.Passed;
            }
            return result;
        }

        private static ControlResult EvaluateVerifiableSingleToken(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out object actual, out BooleanControlData match);
            result.ExpectedValue = "Verify current value";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            result.VerificationResult = VerificationResult.Verify;
            return result;
        }
    
        private static ControlResult EvaluateNullableSingleToken(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out object actual, out BooleanControlData match);
            result.ExpectedValue = "";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid)
            {
                result.VerificationResult = VerificationResult.Passed;
            }
            else
            {
                result.VerificationResult = VerificationResult.Verify;
            }
            return result;
          
        }

        private static ControlResult ExtractSingleToken<TV, TM>(ResourceControl control, JObject resource, out TV actual,
            out TM match, bool validateParameters = true)
        {
            JToken token = null;
            foreach (var jsonPath in control.JsonPath)
            {
                token = resource.SelectToken(jsonPath);
                if (token != null)
                {
                    break;
                }
            }
            var tokenNotFound = token == null;
            var result = ControlResult.Build(control, resource, token, tokenNotFound, VerificationResult.Failed);
            if (tokenNotFound) result.IsTokenNotValid = true;
            try
            {
                if(tokenNotFound)
                {
                    actual = default(TV);
                }
                else
                {
                    var tokenValue = default(TV);
                    bool paramterValueFound = false;
                    // Check if current token is parameter 
                    if (validateParameters && token.Value<String>().CheckIsParameter())
                    {
                        var parameterKey = token.Value<String>().GetParameterKey();
                        if (parameterKey != null)
                        {
                            // Check if parameter value is present in external parameter file
                            if (_externalParametersDict.ContainsKey("parameters"))
                            {
                                JObject externalParameters = _externalParametersDict["parameters"].Value<JObject>();
                                var externalParamValue = externalParameters.Properties().Where(p => p.Name == parameterKey).Select(p => p.Value["value"].Value<TV>());
                                if (externalParamValue != null && externalParamValue.Count() > 0)
                                {
                                    paramterValueFound = true;
                                    tokenValue = externalParamValue.First();
                                }

                            }
                            // If parameter value is not present in external parameter file, check for default value
                            if (!paramterValueFound)
                            {
                                JObject innerParameters = _armTemplate["parameters"].Value<JObject>();
                                tokenValue = innerParameters.Properties().Where(p => p.Name == parameterKey).Select(p => p.Value["defaultValue"].Value<TV>()).FirstOrDefault();
                            }
                        }
                    }
                    else
                    {
                        tokenValue = token.Value<TV>();
              
                    }
                    actual = tokenValue;
                }
            }
            catch (Exception)
            {
                actual = default(TV);
                result.IsTokenNotValid = true;
            }
            match = control.Data.ToObject<TM>();
            return result;
        }

        private static ControlResult ExtractMultiToken<TV, TM>(ResourceControl control, JObject resource,
            out IEnumerable<TV> actual,
            out TM match)
        {
            IEnumerable<JToken> tokens = null;
            foreach (var jsonPath in control.JsonPath)
            {
                tokens = resource.SelectTokens(jsonPath);
                if (tokens != null)
                {
                    break;
                }
            }
            var tokenNotFound = tokens == null;
            var result = ControlResult.Build(control, resource, tokens, tokenNotFound, VerificationResult.Failed);
            if (tokenNotFound) result.IsTokenNotValid = true;
            try
            {
                if (tokenNotFound)
                {
                    actual = default(IEnumerable<TV>);
                }
                else
                {
                    var tokenValues = default(IEnumerable<TV>);
                    bool paramterValueFound = false;
                    // Check if current token is parameter 
                    if (tokens.Values<TV>().FirstOrDefault() != null && tokens.Values<TV>().First().ToString().CheckIsParameter())
                    {
                        var parameterKey = tokens.Values<String>().First().GetParameterKey();
                        if (parameterKey != null)
                        {
                            // Check if parameter value is present in external parameter file
                            if (_externalParametersDict.ContainsKey("parameters"))
                            {
                                JObject externalParameters = _externalParametersDict["parameters"].Value<JObject>();
                                var externalParamValue = externalParameters.Properties().Where(p => p.Name == parameterKey).Select(p => p.Value["value"].Values<TV>());
                                if (externalParamValue != null && externalParamValue.Count() > 0)
                                {
                                    paramterValueFound = true;
                                    tokenValues = externalParamValue.First();
                                }

                            }
                            // If parameter value is not present in external parameter file, check for default value
                            if (!paramterValueFound)
                            {
                                JObject innerParameters = _armTemplate["parameters"].Value<JObject>();
                                tokenValues = innerParameters.Properties().Where(p => p.Name == parameterKey).Select(p => p.Value["defaultValue"].Values<TV>()).FirstOrDefault();
                            }
                        }
                    }
                    else
                    {
                        tokenValues = tokens.Values<TV>();

                    }
                    actual = tokenValues;
                }
                //actual = tokenNotFound ? default(IEnumerable<TV>) : tokens.Values<TV>();
            }
            catch (Exception)
            {
                actual = default(IEnumerable<TV>);
                result.IsTokenNotValid = true;
            }
            match = control.Data.ToObject<TM>();

            return result;
        }

       
    }
}

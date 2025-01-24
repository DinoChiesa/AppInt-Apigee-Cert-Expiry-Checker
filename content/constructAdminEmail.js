function handleOneKeystore(ksdata) {
  return Object.keys(ksdata).map(function (keystoreName) {
    var html = "";
    if (ksdata[keystoreName] && ksdata[keystoreName].length) {
      html +=
        "<table><tbody>\n  <tr><th colspan='4'>Keystore: " +
        keystoreName +
        "</th></tr>\n";
      html +=
        "  <tr>\n" +
        "    <th align='left'>alias</th>\n" +
        "    <th align='left'>subject</th>\n" +
        "    <th align='left'>expiry</th>\n" +
        "    <th align='left'>reason</th>\n" +
        "  </tr>\n";
      html += ksdata[keystoreName]
        .map(function (cert) {
          var row =
            "  <tr>\n" +
            "    <td>" +
            cert.alias +
            "</td>\n" +
            "    <td>" +
            cert.subject +
            "</td>\n" +
            "    <td>" +
            cert.expiry +
            "</td>\n" +
            "    <td>" +
            cert.reason +
            "</td>\n" +
            "  </tr>";
          return row;
        })
        .join("\n");
      html += "\n</tbody></table>\n";
    } else {
      html += "<p>For keystore: " + keystoreName + ", no alerts.</p>\n";
    }
    return html;
  });
}

function handleOneEnv(env) {
  var keys = Object.keys(env);
  var envName = keys[0];
  var html =
    "<h3>Environment <strong><code>" + envName + "</code></strong>:</h3>\n";
  var findings = env[envName];
  if (findings && findings.length) {
    html += findings.map(handleOneKeystore).join("\n");
  } else {
    html += "<p>No keystores</p>\n";
  }
  return html;
}

function executeScript(event) {
  var alertedCerts = event.getParameter("alertedCerts");
  var html = alertedCerts.map(handleOneEnv).join("\n");
  event.setParameter("formattedEmailText", html);
}

function getNeedAlert(certName, soonThreshold) {
  return function (delta) {
    if (delta < 0) return "expired";
    if (delta < soonThreshold) return "expires soon";
    // special case for debugging during development
    //if (certName && certName.startsWith('gts-root-')) return "special";
    return false;
  };
}
/**
 * Function that is called during the JavaScript Task execution.
 * @param {IntegrationEvent} event
 */

function executeScript(event) {
  var soonThreshold = Number(event.getParameter("soonThresholdMs"));
  if (soonThreshold) {
    event.log("have soonThreshold: " + soonThreshold.toFixed(0));
    var certName = event.getParameter("certName");
    var needAlert = getNeedAlert(certName, soonThreshold);
    var expiry = event.getParameter("certExpiry");
    var subject = event.getParameter("certSubject");
    var now = new Date().valueOf();
    expiry = Number(expiry);
    var delta = expiry - now;
    var reason = needAlert(delta);
    if (reason) {
      event.log("reason: " + reason);
      var payload = {
        alias: certName,
        subject: subject,
        expiryDate: expiry,
        expiry: new Date(expiry).toISOString(),
        delta: delta,
        reason: reason,
      };
      event.log("payload: " + JSON.stringify(payload));
      event.log("log A");
      event.setParameter("flagged", payload);
      event.log("log B");
    } else {
      event.log("no reason.");
    }
    event.log("done checking");
  } else {
    event.log("no soonThreshold");
  }
}

function getPair(num, unit) {
  switch (unit) {
    case "s":
      return [num.toFixed(0) + " seconds", num * 1000];
    case "m":
      return [num.toFixed(0) + " minutes", num * 60 * 1000];
    case "h":
      return [num.toFixed(0) + " hours", num * 60 * 60 * 1000];
    case "d":
      return [num.toFixed(0) + " days", num * 24 * 60 * 60 * 1000];
    case "y":
      return [num.toFixed(0) + " years", num * 365 * 24 * 60 * 60 * 1000];
    default:
      return ["30 days", 30 * 24 * 60 * 60 * 1000]; // thirty days by default
    //throw new Error('Invalid timespan format');
  }
}

function digestTimespan(timespan) {
  if (timespan) {
    const num = parseInt(timespan);
    const unit = timespan.slice(-1);
    const pair = getPair(num, unit);

    return {
      ms: pair[1],
      friendly: pair[0],
    };
  }
  const defaultPair = getPair("30", "d");

  return {
    ms: defaultPair[1],
    friendly: defaultPair[0],
  };
}

function executeScript(event) {
  var configuredThreshold = event.getParameter("`CONFIG_soonThreshold`");
  var digest = digestTimespan(configuredThreshold);

  event.setParameter("soonThresholdMs", digest.ms);
  event.setParameter("friendlyTimespan", digest.friendly);

  // copy CONFIG variables to sidestep runtime bug b/385006505
  event.setParameter(
    "emailAddress",
    event.getParameter("`CONFIG_emailAddress`"),
  );
  event.setParameter(
    "tableHeaderBg",
    event.getParameter("`CONFIG_tableHeaderBg`"),
  );
  event.setParameter(
    "tableHeaderFg",
    event.getParameter("`CONFIG_tableHeaderFg`"),
  );
}

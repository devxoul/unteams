export const TEAMS_URL = "https://teams.cloud.microsoft/";

// Hosts Teams and Microsoft sign-in navigate through. Anything else opens in the default browser.
const INTERNAL_DOMAINS = [
  "cloud.microsoft",
  "microsoft.com",
  "microsoftonline.com",
  "microsoftonline-p.com",
  "live.com",
  "office.com",
  "office.net",
  "office365.com",
  "sharepoint.com",
  "skype.com",
  "msauth.net",
  "msftauth.net",
  "msauthimages.net",
  "msftauthimages.net",
  "windows.net",
  "microsoftazuread-sso.com",
  "azure.com",
  "aka.ms",
];

export type Route = "app" | "browser" | "drop";

export function isInternal(url: string): boolean {
  try {
    const host = new URL(url).hostname.toLowerCase();
    return INTERNAL_DOMAINS.some((domain) => host === domain || host.endsWith(`.${domain}`));
  } catch {
    return false;
  }
}

// Teams and sign-in stay in the app, followed links go to the browser, and other schemes are dropped: Teams uses
// msteams: links to hand off to the desktop client, which is exactly what this app replaces.
export function route(url: string): Route {
  const scheme = url.split(":", 1)[0]?.toLowerCase();
  switch (scheme) {
    case "http":
    case "https":
      return isInternal(url) ? "app" : "browser";
    case "about":
    case "blob":
    case "data":
      return "app";
    case "mailto":
    case "tel":
      return "browser";
    default:
      return "drop";
  }
}

/** Reads the unread count Teams puts in the page title, e.g. "(3) Chat | Microsoft Teams". */
export function unreadCount(title: string): number {
  const match = /^\((\d+)\)/.exec(title);
  return match ? Number(match[1]) : 0;
}

export function badgeLabel(count: number): string {
  if (count === 0) return "";
  return count < 0 ? "\u2022" : String(count);
}

import { describe, expect, test } from "bun:test";

import { badgeLabel, isInternal, route, unreadCount } from "./teams";

describe("isInternal", () => {
  test("accepts Microsoft domains and their subdomains", () => {
    expect(isInternal("https://teams.cloud.microsoft/")).toBe(true);
    expect(isInternal("https://login.microsoftonline.com/common")).toBe(true);
    expect(isInternal("https://contoso.sharepoint.com/sites/x")).toBe(true);
  });

  test("rejects lookalike hosts and invalid URLs", () => {
    expect(isInternal("https://evilmicrosoft.com/")).toBe(false);
    expect(isInternal("https://microsoft.com.example.com/")).toBe(false);
    expect(isInternal("not a url")).toBe(false);
  });
});

describe("route", () => {
  test("keeps Teams and sign-in in the app", () => {
    expect(route("https://teams.cloud.microsoft/v2/")).toBe("app");
    expect(route("about:blank")).toBe("app");
    expect(route("blob:https://teams.cloud.microsoft/1234")).toBe("app");
  });

  test("sends other sites, mail and phone links to the browser", () => {
    expect(route("https://example.com/")).toBe("browser");
    expect(route("mailto:user@example.com")).toBe("browser");
    expect(route("tel:+15555550100")).toBe("browser");
  });

  test("drops other schemes", () => {
    expect(route("msteams:/l/meetup-join/x")).toBe("drop");
    expect(route("javascript:alert(1)")).toBe("drop");
  });
});

describe("unreadCount", () => {
  test("reads the count Teams puts in the title", () => {
    expect(unreadCount("(3) Chat | Microsoft Teams")).toBe(3);
    expect(unreadCount("Chat | Microsoft Teams")).toBe(0);
    expect(unreadCount("Chat (3) | Microsoft Teams")).toBe(0);
  });
});

describe("badgeLabel", () => {
  test("shows a count, a dot for unknown unread, and nothing at zero", () => {
    expect(badgeLabel(5)).toBe("5");
    expect(badgeLabel(-1)).toBe("\u2022");
    expect(badgeLabel(0)).toBe("");
  });
});

import { describe, expect, test } from "bun:test";

import { badgeLabel, isInternal, route, unreadCount, webLink } from "./teams";

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

describe("webLink", () => {
  test("turns msteams links into Teams web URLs", () => {
    expect(webLink("msteams:/l/meetup-join/19%3ameeting%40thread.v2/0?context=x")).toBe(
      "https://teams.microsoft.com/l/meetup-join/19%3ameeting%40thread.v2/0?context=x",
    );
    expect(webLink("msteams://teams.microsoft.com/l/chat/0/0?users=user@example.com")).toBe(
      "https://teams.microsoft.com/l/chat/0/0?users=user@example.com",
    );
    expect(webLink("MSTEAMS:/l/app/x")).toBe("https://teams.microsoft.com/l/app/x");
  });

  test("ignores links that would leave Microsoft or aren't msteams links", () => {
    expect(webLink("msteams:////example.com/x")).toBeUndefined();
    expect(webLink("msteams:/\\example.com/x")).toBeUndefined();
    expect(webLink("msteams:javascript://teams.microsoft.com/%0aalert(1)")).toBeUndefined();
    expect(webLink("msteams:https://attacker.web.core.windows.net/")).toBeUndefined();
    expect(webLink("msteams:https://teams.microsoft.com/l/chat")).toBeUndefined();
    expect(webLink("https://teams.microsoft.com/l/chat")).toBeUndefined();
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

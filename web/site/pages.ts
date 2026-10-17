/* Every page of the site, in one list.

   To add a page:
   1. Write the HTML file (copy the <head> of guide.html: it only needs charset, viewport,
      the "js" script and <!--site:head-->, and <!--site:learn--> in the footer).
   2. Add an entry below.
   The build then adds it to the Vite inputs, sitemap.xml, llms.txt and llms-full.txt, gives it
   its title, description, canonical URL, social cards and structured data (with a breadcrumb),
   and, when it has `learn`, lists it under Learn in every page's footer. */

export const SITE = "https://glasspad.sohamaggarwal.com";
export const REPO = "https://github.com/Soham109/glasspad";
export const VERSION = "0.1.2";
export const RELEASE = `${REPO}/releases/tag/v${VERSION}`;
export const RELEASED = "2026-10-16";

export interface Page {
  /** URL path, without .html: "/" or "/guide" */
  path: string;
  /** source HTML file, relative to web/ */
  file: string;
  /** <title>: what the page is, then Glasspad. Keep it under about 60 characters. */
  title: string;
  /** meta description and social card text: 120 to 160 characters */
  description: string;
  /** date of the last real change to the page, YYYY-MM-DD (sitemap lastmod) */
  lastmod: string;
  /** one line for llms.txt */
  summary: string;
  /** breadcrumb name; every page but home has one */
  crumb?: string;
  /** link text for the footer's Learn list. Leave out to keep the page out of it. */
  learn?: string;
  /** "article" for pages that read like one */
  ogType?: "website" | "article";
  /** FAQ list from content.ts shown on this page (rendered at <!--site:faq-->, and as FAQPage data) */
  faq?: string;
  /** extra schema.org nodes for this page */
  schema?: object[];
}

export const pages: Page[] = [
  {
    path: "/",
    file: "index.html",
    title: "Glasspad: your iPhone as a Mac trackpad, keyboard and remote",
    description: "Glasspad is a free, open source app that turns your iPhone into a control surface for your Mac: trackpad, keyboard, remote, Dock, app buttons and split screen.",
    lastmod: "2026-10-16",
    summary: "What Glasspad does, the demo film, how to install it, and common questions.",
    faq: "home",
  },
  {
    path: "/guide",
    file: "guide.html",
    title: "Glasspad Guide: every mode, Layouts and help",
    description: "How to use Glasspad on your iPhone and Mac: setting up, Trackpad, Keyboard, Media, Remote, Actions, Displays, split screen Layouts, StandBy, themes and help.",
    lastmod: "2026-10-16",
    summary: "How to use every mode, Layouts, Actions, StandBy and themes, how Glasspad compares with similar tools, and help.",
    crumb: "Guide",
    ogType: "article",
    faq: "guide",
  },
];

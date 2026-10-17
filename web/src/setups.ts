/* The five setups' captions on the home page. scenes.ts shows them under the drawn rooms, and the
   build (site/plugin.ts) writes them into the HTML, so they can be read without JavaScript. */

export const SETUPS = {
  desk: { key: "desk", title: "Desk", text: "Trackpad and Actions side by side on a stand. Tap Split Screen and two windows share the display." },
  studio: { key: "studio", title: "Studio", text: "Trackpad, Media and Actions on one screen. Final Cut Pro is in front, so Actions shows its buttons: Play, Blade, Mark In. More than 70 apps get their own." },
  couch: { key: "couch", title: "Couch", text: "Remote over the trackpad. Its pad works like the Siri Remote: tap to pause, swipe to skip 10 seconds, up or down for volume. The keys follow the player." },
  presenter: { key: "presenter", title: "Presenter", text: "Present over the trackpad: Next and Back as big as your thumb, a timer, and a laser you steer with one finger." },
  standby: { key: "standby", title: "StandBy", text: "On the nightstand: Clock beside Now Playing, in dim red when the room goes dark." },
};

/** One caption as scenes.ts draws it in #ucCap. */
export const caption = (s: { title: string; text: string }) => `<b>${s.title}</b><span>${s.text}</span>`;

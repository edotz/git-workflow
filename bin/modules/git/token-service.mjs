#!/usr/bin/env node
import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { createAppAuth } from "@octokit/auth-app";

const config = JSON.parse(readFileSync(new URL("../../config/token-service.json", import.meta.url), "utf8"));
const appId = process.env.TOKEN_SERVICE_APP_ID;
const keyPath = process.env.TOKEN_SERVICE_KEY_PATH;
const port = Number(process.env.TOKEN_SERVICE_PORT || 8790);
const host = process.env.TOKEN_SERVICE_HOST || "127.0.0.1";
const org = process.env.TOKEN_SERVICE_ORG || config.org;

if (!appId || !keyPath) {
  console.error("TOKEN_SERVICE_APP_ID and TOKEN_SERVICE_KEY_PATH are required");
  process.exit(1);
}

const privateKey = readFileSync(keyPath, "utf8");
if (!privateKey.includes("PRIVATE KEY")) {
  console.error(`no private key in ${keyPath}`);
  process.exit(1);
}
const auth = createAppAuth({ appId, privateKey });
const api = "https://api.github.com";
const repoForm = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

class Refusal extends Error {
  constructor(status, reason) {
    super(reason);
    this.status = status;
  }
}

async function github(path, token) {
  const res = await fetch(`${api}${path}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "git-workflow-token-service",
    },
  });
  const body = res.status === 204 ? {} : await res.json().catch(() => ({}));
  return { status: res.status, body };
}

async function memberLogin(developerToken) {
  const user = await github("/user", developerToken);
  if (user.status !== 200 || !user.body.login) throw new Refusal(401, "login not accepted");
  const membership = await github(`/user/memberships/orgs/${org}`, developerToken);
  if (membership.status !== 200 || membership.body.state !== "active") {
    throw new Refusal(403, "not a member");
  }
  return user.body.login;
}

async function installationToken(owner, name, permissions) {
  const { token: jwt } = await auth({ type: "app" });
  const installation = await github(`/repos/${owner}/${name}/installation`, jwt);
  if (installation.status !== 200 || !installation.body.id) {
    throw new Refusal(404, "repository not installed");
  }
  const issued = await auth({
    type: "installation",
    installationId: installation.body.id,
    repositoryNames: [name],
    permissions,
    refresh: true,
  });
  return issued;
}

async function handle(req) {
  if (req.method !== "POST" || req.url !== "/token") throw new Refusal(404, "no such endpoint");
  const header = req.headers.authorization || "";
  const developerToken = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!developerToken) throw new Refusal(401, "login not accepted");

  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 4096) throw new Refusal(413, "request too large");
  }
  let request;
  try {
    request = JSON.parse(raw);
  } catch {
    throw new Refusal(400, "request is not JSON");
  }
  const permissions = config.sets[request.set];
  if (!permissions) throw new Refusal(400, "permission set unknown");
  if (typeof request.repo !== "string" || !repoForm.test(request.repo)) {
    throw new Refusal(400, "repository must be owner/name");
  }
  const [owner, name] = request.repo.split("/");
  if (owner.toLowerCase() !== org.toLowerCase()) throw new Refusal(403, "repository not in the organisation");

  const login = await memberLogin(developerToken);
  const issued = await installationToken(owner, name, permissions);
  console.log(`issued login=${login} repo=${request.repo} set=${request.set}`);
  return {
    token: issued.token,
    expires_at: issued.expiresAt,
    permissions: issued.permissions,
    repository: issued.repositoryNames,
  };
}

const server = createServer(async (req, res) => {
  const reply = (status, body) => {
    res.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    res.end(JSON.stringify(body));
  };
  try {
    reply(200, await handle(req));
  } catch (error) {
    if (error instanceof Refusal) {
      console.log(`refused status=${error.status} reason=${error.message}`);
      reply(error.status, { error: error.message });
    } else {
      console.log("failed unexpected error");
      reply(502, { error: "token service failed" });
    }
  }
});
server.listen(port, host, () => console.log(`token service listening on ${host}:${server.address().port} for org ${org}`));

require('dotenv').config();
const { Client, GatewayIntentBits } = require('discord.js');

async function connect() {
  const token = process.env.DISCORD_TOKEN;
  const guildId = process.env.GUILD_ID;

  if (!token || !guildId) {
    console.error('❌ الملف .env ناقص: تأكد من وجود DISCORD_TOKEN و GUILD_ID');
    process.exit(1);
  }

  const client = new Client({ intents: [GatewayIntentBits.Guilds] });
  await client.login(token);

  await new Promise((resolve) => client.once('ready', resolve));

  const guild = await client.guilds.fetch(guildId);
  await guild.roles.fetch();
  await guild.channels.fetch();

  const me = await guild.members.fetchMe();
  if (!me.permissions.has('Administrator') && !me.permissions.has('ManageRoles')) {
    console.warn('⚠️  تحذير: البوت لا يملك صلاحية Manage Roles/Administrator — قد تفشل بعض العمليات.');
  }

  return { client, guild };
}

module.exports = { connect };

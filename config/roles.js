// ترتيب المصفوفة = ترتيب الرولات في Discord من الأعلى للأسفل (index 0 = الأعلى)
// permissions: مفاتيح PermissionFlagsBits في discord.js — راجع lib/discordClient.js
//
// ملاحظة تصميمية مهمة (per الدوكيومنت): أدوار الأقسام (شرطة/إسعاف/قضاء...) والأعمال والمجتمع
// لا تحصل على صلاحيات Discord إدارية عامة — وصولها يتم فقط عبر Channel Overwrites
// في config/categories.js، تماشيًا مع "لا نعطي Role صلاحية أعلى من حاجته".

const BASE = ['SendMessages', 'AddReactions', 'AttachFiles', 'EmbedLinks', 'Connect', 'Speak', 'UseExternalEmojis'];
const MGMT_PERMS = ['ManageChannels', 'ManageMessages', 'ManageEvents', 'ViewAuditLog', 'ModerateMembers', 'ManageThreads', 'ManageNicknames'];
const EXEC_PERMS = ['ManageGuild', 'ManageRoles', 'ManageChannels', 'ManageWebhooks', 'ManageEvents', 'ViewAuditLog', 'ManageMessages', 'KickMembers', 'BanMembers', 'ModerateMembers', 'ManageNicknames', 'ManageThreads'];
const DEV_PERMS = [...BASE, 'ManageThreads'];

module.exports = [
  // المستوى 1 — Ownership
  { name: '👑 Owner', color: '#F1C40F', hoist: true, mentionable: false, permissions: ['Administrator'] },

  // المستوى 2 — Executive
  { name: '👑 Executive', color: '#E67E22', hoist: true, permissions: EXEC_PERMS },
  { name: '🧭 Director', color: '#E67E22', hoist: true, permissions: EXEC_PERMS },

  // المستوى 3 — Management
  { name: '🛡️ Server Manager', color: '#D35400', hoist: true, permissions: MGMT_PERMS },
  { name: '⚙️ Operations Manager', color: '#D35400', hoist: true, permissions: MGMT_PERMS },
  { name: '👥 Community Manager', color: '#D35400', hoist: true, permissions: MGMT_PERMS },
  { name: '📊 Management', color: '#D35400', hoist: true, permissions: MGMT_PERMS },

  // المستوى 4 — Development
  { name: '💻 Lead Developer', color: '#5865F2', hoist: true, permissions: [...DEV_PERMS, 'ManageMessages'] },
  { name: '💻 Developer', color: '#5865F2', permissions: DEV_PERMS },
  { name: '🗄️ Database Administrator', color: '#5865F2', permissions: DEV_PERMS },
  { name: '🧪 QA', color: '#5865F2', permissions: BASE },
  { name: '🎨 Designer', color: '#5865F2', permissions: BASE },

  // المستوى 5 — Staff
  { name: '🛡️ Head Administrator', color: '#C0392B', hoist: true, permissions: [...BASE, 'KickMembers', 'BanMembers', 'ModerateMembers', 'ManageMessages', 'ManageThreads', 'ViewAuditLog', 'ManageNicknames'] },
  { name: '🔨 Administrator', color: '#C0392B', hoist: true, permissions: [...BASE, 'KickMembers', 'BanMembers', 'ModerateMembers', 'ManageMessages', 'ManageThreads', 'ManageNicknames'] },
  { name: '🔧 Moderator', color: '#C0392B', hoist: true, permissions: [...BASE, 'ModerateMembers', 'ManageMessages', 'ManageThreads', 'KickMembers'] },
  { name: '🎫 Support', color: '#C0392B', permissions: [...BASE, 'ManageThreads'] },

  // Police
  { name: '🚔 Police Chief', color: '#2980B9', hoist: true, permissions: BASE },
  { name: '🚔 Deputy Chief', color: '#2980B9', permissions: BASE },
  { name: '🚔 Police Command', color: '#2980B9', permissions: BASE },
  { name: '🚔 Police Officer', color: '#2980B9', permissions: BASE },
  { name: '🚔 Police Recruit', color: '#2980B9', permissions: BASE },

  // EMS
  { name: '🏥 EMS Chief', color: '#27AE60', hoist: true, permissions: BASE },
  { name: '🏥 EMS Command', color: '#27AE60', permissions: BASE },
  { name: '🏥 Paramedic', color: '#27AE60', permissions: BASE },
  { name: '🏥 EMS Recruit', color: '#27AE60', permissions: BASE },

  // MOJ
  { name: '⚖️ Chief Justice', color: '#8E44AD', hoist: true, permissions: BASE },
  { name: '⚖️ Judge', color: '#8E44AD', permissions: BASE },
  { name: '⚖️ Prosecutor', color: '#8E44AD', permissions: BASE },
  { name: '⚖️ Lawyer', color: '#8E44AD', permissions: BASE },
  { name: '⚖️ Legal Staff', color: '#8E44AD', permissions: BASE },

  // CIA
  { name: '🕵️ CIA Director', color: '#34495E', hoist: true, permissions: BASE },
  { name: '🕵️ CIA Command', color: '#34495E', permissions: BASE },
  { name: '🕵️ CIA Agent', color: '#34495E', permissions: BASE },
  { name: '🕵️ CIA Recruit', color: '#34495E', permissions: BASE },

  // Government
  { name: '🏛️ Government Official', color: '#16A085', hoist: true, permissions: BASE },
  { name: '🏛️ Government Employee', color: '#16A085', permissions: BASE },

  // Business
  { name: '🏢 Business Owner', color: '#F39C12', hoist: true, permissions: BASE },
  { name: '🏢 Business Manager', color: '#F39C12', permissions: BASE },
  { name: '👔 Business Employee', color: '#F39C12', permissions: BASE },
  { name: '🚘 Car Dealer', color: '#F39C12', permissions: BASE },
  { name: '🍔 Restaurant', color: '#F39C12', permissions: BASE },
  { name: '🔧 Mechanic', color: '#F39C12', permissions: BASE },
  { name: '🚕 Taxi', color: '#F39C12', permissions: BASE },

  // Community
  { name: '🎥 Content Creator', color: '#E91E63', permissions: BASE },
  { name: '📸 Media', color: '#E91E63', permissions: BASE },
  { name: '⭐ VIP', color: '#F1C40F', permissions: BASE },
  { name: '🏆 Event Winner', color: '#F1C40F', permissions: BASE },
  { name: '🤝 Partner', color: '#1ABC9C', permissions: BASE },
  { name: '✅ Verified', color: '#95A5A6', permissions: BASE },
  { name: '👤 Citizen', color: '#95A5A6', permissions: BASE },

  // Automated
  { name: '🤖 Bot', color: '#7289DA', hoist: true, permissions: [...BASE, 'ManageMessages', 'ManageWebhooks'] },
  { name: '🔴 Muted', color: '#2C3E50', permissions: [] },
  { name: '⏳ Pending Verification', color: '#7F8C8D', permissions: [] },
];

const mongoose = require('mongoose');

const auditLogSchema = new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'Utilisateur', default: null },
  userEmail: { type: String, default: '' },
  action: { type: String, required: true },
  targetType: { type: String, default: '' },
  targetId: { type: mongoose.Schema.Types.ObjectId, default: null },
  metadata: { type: mongoose.Schema.Types.Mixed, default: {} },
  ip: { type: String, default: '' }
}, { timestamps: true });

module.exports = mongoose.model('AuditLog', auditLogSchema);

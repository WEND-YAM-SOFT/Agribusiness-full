const nodemailer = require('nodemailer');

function getMailConfig() {
  return {
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT || 587),
    secure: String(process.env.SMTP_SECURE || 'false').toLowerCase() === 'true',
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
    fromEmail: process.env.SMTP_FROM_EMAIL || process.env.SMTP_USER,
    fromName: process.env.SMTP_FROM_NAME || 'AgriBusiness',
    replyTo: process.env.SMTP_REPLY_TO || process.env.SMTP_FROM_EMAIL || process.env.SMTP_USER,
    resetBaseUrl: process.env.PASSWORD_RESET_URL || process.env.APP_WEB_URL || ''
  };
}

function isMailConfigured() {
  const config = getMailConfig();
  return Boolean(config.host && config.port && config.user && config.pass && config.fromEmail);
}

function createTransporter() {
  const config = getMailConfig();

  return nodemailer.createTransport({
    host: config.host,
    port: config.port,
    secure: config.secure,
    auth: {
      user: config.user,
      pass: config.pass
    }
  });
}

function buildResetUrl(token, email) {
  const { resetBaseUrl } = getMailConfig();
  if (!resetBaseUrl) return '';

  const separator = resetBaseUrl.includes('?') ? '&' : '?';
  return `${resetBaseUrl}${separator}token=${encodeURIComponent(token)}&email=${encodeURIComponent(email)}`;
}

function buildPasswordResetEmail({ userName, email, token, expiresMinutes }) {
  const resetUrl = buildResetUrl(token, email);
  const title = 'Réinitialisation de votre mot de passe AgriBusiness';
  const intro = `Bonjour ${userName || ''},`; 
  const instructions = resetUrl
    ? 'Cliquez sur le bouton ci-dessous pour réinitialiser votre mot de passe ou utilisez le code de sécurité indiqué.'
    : 'Utilisez le code de sécurité ci-dessous dans l\'application pour réinitialiser votre mot de passe.';

  const html = `
    <div style="font-family:Arial,sans-serif;background:#f5f7f6;padding:24px;color:#1f2937;">
      <div style="max-width:640px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #dbe5dd;">
        <div style="background:linear-gradient(135deg,#0b5d3b,#2e7d32);padding:24px;color:#ffffff;">
          <h1 style="margin:0;font-size:24px;">AgriBusiness</h1>
          <p style="margin:8px 0 0 0;font-size:14px;opacity:0.92;">Réinitialisation du mot de passe</p>
        </div>
        <div style="padding:24px;">
          <p style="margin-top:0;">${intro}</p>
          <p>${instructions}</p>
          ${resetUrl ? `<p style="margin:24px 0;"><a href="${resetUrl}" style="display:inline-block;background:#2e7d32;color:#ffffff;text-decoration:none;padding:14px 20px;border-radius:10px;font-weight:700;">Réinitialiser mon mot de passe</a></p>` : ''}
          <div style="background:#f0fdf4;border:1px solid #cce7d4;border-radius:12px;padding:16px;margin:20px 0;">
            <div style="font-size:12px;color:#4b5563;margin-bottom:8px;">Code de sécurité</div>
            <div style="font-size:22px;font-weight:700;letter-spacing:1px;color:#0b5d3b;word-break:break-all;">${token}</div>
          </div>
          <p>Ce code expire dans ${expiresMinutes} minutes.</p>
          <p style="color:#6b7280;font-size:13px;">Si vous n'êtes pas à l'origine de cette demande, ignorez simplement cet email.</p>
        </div>
      </div>
    </div>
  `;

  const text = [
    title,
    '',
    intro,
    instructions,
    '',
    resetUrl ? `Lien: ${resetUrl}` : null,
    `Code: ${token}`,
    `Expiration: ${expiresMinutes} minutes`,
    '',
    'Si vous n\'êtes pas à l\'origine de cette demande, ignorez simplement cet email.'
  ].filter(Boolean).join('\n');

  return { subject: title, html, text };
}

async function sendPasswordResetEmail({ to, userName, token, expiresMinutes = 30 }) {
  if (!isMailConfigured()) {
    throw new Error('Le service email n\'est pas configuré. Vérifiez les variables SMTP.');
  }

  const config = getMailConfig();
  const transporter = createTransporter();
  const { subject, html, text } = buildPasswordResetEmail({
    userName,
    email: to,
    token,
    expiresMinutes
  });

  await transporter.sendMail({
    from: `${config.fromName} <${config.fromEmail}>`,
    to,
    replyTo: config.replyTo,
    subject,
    html,
    text
  });
}

module.exports = {
  getMailConfig,
  isMailConfigured,
  sendPasswordResetEmail
};

/**
 * Email Service
 * Handles transactional emails (OTPs, notifications) over SMTP via Truehost Workplace mail servers.
 */

import nodemailer from 'nodemailer';
import fs from 'fs';
import { env } from '../config/env.js';
import { marketingTemplates } from '../templates/marketing.template.js';

class EmailService {
  constructor() {
    this.transporter = null;
    this.sentEmails = [];
  }

  getPassword() {
    if (env.SMTP_PASS) return env.SMTP_PASS;
    try {
      const credPath = '/root/backups/mail-credentials';
      if (fs.existsSync(credPath)) {
        return fs.readFileSync(credPath, 'utf8').trim();
      }
    } catch (_) {
      // ignore
    }
    return '';
  }

  getTransporter() {
    if (this.transporter) return this.transporter;
    const pass = this.getPassword();
    if (!pass) return null;

    this.transporter = nodemailer.createTransport({
      host: env.SMTP_HOST,
      port: env.SMTP_PORT,
      secure: env.SMTP_SECURE, // true for 465, false for 587
      auth: {
        user: env.SMTP_USER,
        pass: pass,
      },
    });
    return this.transporter;
  }

  async sendMail({ to, from, subject, text, html }) {
    const transporter = this.getTransporter();
    const mailOptions = {
      from: from || env.SMTP_FROM,
      to,
      subject,
      text,
      html,
    };

    if (env.isTest || !transporter) {
      this.sentEmails.push(mailOptions);
      return { messageId: `mock-${Date.now()}`, delivered: false, mock: true };
    }

    return await transporter.sendMail(mailOptions);
  }

  /**
   * Dispatches a branded marketing campaign email.
   * Defaults to sender: Cosmic-Gen <marketing@cosmic-gen.com>
   */
  async sendMarketingCampaign({
    to,
    from = 'Cosmic-Gen <marketing@cosmic-gen.com>',
    subject,
    type = 'image', // 'image' | 'video' | 'audio' | 'digest'
    options = {},
  }) {
    let html = '';
    if (type === 'video') {
      html = marketingTemplates.createVideoCampaign({ headline: subject, ...options });
    } else if (type === 'audio') {
      html = marketingTemplates.createAudioCampaign({ headline: subject, ...options });
    } else if (type === 'digest') {
      html = marketingTemplates.createMultiMediaDigest({ headline: subject, ...options });
    } else {
      html = marketingTemplates.createImageCampaign({ headline: subject, ...options });
    }

    const plainText = options.bodyText || options.introText || subject;
    return await this.sendMail({
      to,
      from,
      subject,
      text: `${subject}\n\n${plainText}\n\nVisit Cosmic-Gen: ${options.ctaUrl || 'https://cosmic-gen.com'}`,
      html,
    });
  }

  async sendOtpEmail(to, otpCode, purpose = 'email_verification') {
    const isReset = purpose === 'password_reset';
    const title = isReset ? 'Password Reset Code' : 'Email Verification Code';
    const subject = `Your Cosmic-Gen ${title}: ${otpCode}`;
    const text = `Hello,\n\nYour Cosmic-Gen verification code is: ${otpCode}\nThis code will expire in 10 minutes.\n\nIf you did not request this code, you can safely ignore this email.\n\nBest regards,\nCosmic-Gen Team`;

    const html = `
      <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 32px 24px; background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 12px; color: #1e293b;">
        <div style="text-align: center; margin-bottom: 24px;">
          <h1 style="font-size: 24px; font-weight: 800; color: #4f46e5; margin: 0; letter-spacing: -0.5px;">Cosmic-Gen</h1>
          <p style="font-size: 13px; color: #64748b; margin-top: 4px;">AI Image & Media Studio</p>
        </div>
        <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 24px; text-align: center;">
          <p style="font-size: 15px; margin: 0 0 16px 0; color: #334155;">
            Use the following code to complete your <strong>${isReset ? 'password reset' : 'email verification'}</strong>:
          </p>
          <div style="font-size: 36px; font-weight: 800; letter-spacing: 8px; color: #4338ca; padding: 12px 20px; background-color: #eef2ff; border-radius: 8px; display: inline-block; font-family: monospace;">
            ${otpCode}
          </div>
          <p style="font-size: 13px; color: #64748b; margin: 16px 0 0 0;">
            This code will expire in <strong>10 minutes</strong>.
          </p>
        </div>
        <p style="font-size: 13px; color: #94a3b8; margin-top: 24px; text-align: center;">
          If you didn't request this code, you can safely ignore this email.
        </p>
        <hr style="border: none; border-top: 1px solid #f1f5f9; margin: 24px 0;" />
        <div style="text-align: center; font-size: 12px; color: #94a3b8;">
          &copy; ${new Date().getFullYear()} Cosmic-Gen &bull; <a href="https://cosmic-gen.com" style="color: #6366f1; text-decoration: none;">cosmic-gen.com</a>
        </div>
      </div>
    `;

    return await this.sendMail({ to, subject, text, html });
  }
}

export const emailService = new EmailService();

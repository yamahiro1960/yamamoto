import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
// Resend で送信者として登録済みのメールアドレスに変更してください
const FROM_ADDRESS = Deno.env.get('MAIL_FROM') ?? 'noreply@example.com';
// 管理者通知先。未設定なら管理者通知は送信しません。
const ADMIN_NOTIFY_EMAIL = Deno.env.get('ADMIN_NOTIFY_EMAIL') ?? '';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

async function sendWithResend(to: string[], subject: string, html: string) {
  const resendRes = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from: FROM_ADDRESS,
      to,
      subject,
      html,
    }),
  });

  const data = await resendRes.json();
  return { ok: resendRes.ok, status: resendRes.status, data };
}

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  if (!RESEND_API_KEY) {
    return new Response(JSON.stringify({ error: 'RESEND_API_KEY is not set' }), {
      status: 500,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  let body: Record<string, string>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), {
      status: 400,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  const {
    to_email,
    to_name,
    form_title,
    submitted_at,
    form_url,
    edit_url,
    edit_deadline,
    edit_limit,
  } = body;

  // 簡易バリデーション
  if (!to_email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to_email)) {
    return new Response(JSON.stringify({ error: 'Invalid to_email' }), {
      status: 400,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  const editSection = edit_url
    ? `
      <p>回答内容の修正は以下のリンクから行えます（${edit_deadline ?? '開催日の3日前まで'}・${edit_limit ?? '回数無制限'}）。</p>
      <p><a href="${edit_url}">${edit_url}</a></p>
    `
    : '';

  const htmlBody = `
    <p>${to_name ?? 'ご回答者様'} 様</p>
    <p>「${form_title ?? 'アンケート'}」へのご回答ありがとうございました。</p>
    <p>以下の内容で受け付けました。</p>
    <ul>
      <li>受付日時: ${submitted_at ?? ''}</li>
      <li>フォームURL: <a href="${form_url ?? ''}">${form_url ?? ''}</a></li>
    </ul>
    ${editSection}
    <p>ご不明な点がございましたら、主催者へお問い合わせください。</p>
  `.trim();

  const respondentResult = await sendWithResend(
    [to_email],
    `【受付完了】${form_title ?? 'アンケート'} へのご回答`,
    htmlBody,
  );

  if (!respondentResult.ok) {
    console.error('Respondent email send failed:', respondentResult.data);
    return new Response(JSON.stringify({ error: respondentResult.data }), {
      status: respondentResult.status,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  let adminNotification = { enabled: false, sent: false };
  if (ADMIN_NOTIFY_EMAIL && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(ADMIN_NOTIFY_EMAIL)) {
    adminNotification = { enabled: true, sent: false };

    const adminHtml = `
      <p>新しい申込がありました。</p>
      <ul>
        <li>フォーム名: ${form_title ?? 'アンケート'}</li>
        <li>申込者名: ${to_name ?? '未入力'}</li>
        <li>申込者メール: ${to_email}</li>
        <li>受付日時: ${submitted_at ?? ''}</li>
        <li>フォームURL: <a href="${form_url ?? ''}">${form_url ?? ''}</a></li>
      </ul>
    `.trim();

    const adminResult = await sendWithResend(
      [ADMIN_NOTIFY_EMAIL],
      `【新規申込通知】${form_title ?? 'アンケート'}`,
      adminHtml,
    );

    if (!adminResult.ok) {
      console.error('Admin notification send failed:', adminResult.data);
    } else {
      adminNotification = { enabled: true, sent: true };
    }
  }

  return new Response(JSON.stringify({ id: respondentResult.data.id, adminNotification }), {
    status: 200,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
});

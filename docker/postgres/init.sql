-- Extensionの有効化 (UUID生成用)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 更新日時自動更新用の関数定義
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 1. Users Table (認証・基本ID管理)
-- プロジェクト定義には明記ありませんが、ProfilesやMembersの正規化に必須のため定義
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

TRIGGER_UPDATE_TIMESTAMP(users);

-- 2. Profiles Table (プロフィール帳)
-- 拡張性を担保するため質問項目はJSONBで保持
CREATE TABLE profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    display_name VARCHAR(100) NOT NULL,
    bio TEXT,
    -- テンプレート形式の回答データ (例: {"hobby": "Retro Games", "dream": "Astronaut"})
    questions JSONB NOT NULL DEFAULT '{}'::jsonb, 
    -- バインダーUIの設定など (例: {"theme_color": "#ff0000", "font": "mincho"})
    theme_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

TRIGGER_UPDATE_TIMESTAMP(profiles);

-- 3. Groups Table (日記帳グループ)
CREATE TABLE groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_public BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

TRIGGER_UPDATE_TIMESTAMP(groups);

-- 4. Group Members Table (所属と順番管理)
CREATE TABLE group_members (
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- 執筆順序 (Turn-based logic用)
    order_index INTEGER NOT NULL,
    -- ユーザーごとのピン留め設定
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    PRIMARY KEY (group_id, user_id),
    
    -- [CRITICAL FIX] 同じグループ内で同じ order_index を持つことを防ぐ
    -- これにより「1番目の人が2人いる」状態をDBレベルで阻止する
    CONSTRAINT uq_group_member_order UNIQUE (group_id, order_index)
);

CREATE INDEX idx_group_members_user_id ON group_members(user_id);
-- ここでは明示的な検索用として残します。
CREATE INDEX idx_group_members_order ON group_members(group_id, order_index);

-- ... (以降変更なし)

-- 5. Entries Table (日記投稿)
CREATE TABLE entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    -- 画像URLリスト (最大4枚想定だがDB側は柔軟に配列で保持)
    image_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

TRIGGER_UPDATE_TIMESTAMP(entries);

-- 日記のタイムライン表示用インデックス (最新順取得を高速化)
CREATE INDEX idx_entries_group_created ON entries(group_id, created_at DESC);

-- トリガー適用用のマクロ的記述 (Postgres標準SQL構文)
CREATE TRIGGER update_users_modtime BEFORE UPDATE ON users FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_profiles_modtime BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_groups_modtime BEFORE UPDATE ON groups FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_entries_modtime BEFORE UPDATE ON entries FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

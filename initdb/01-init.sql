-- ==============================================================
-- 首次初始化脚本：仅执行一次
-- ==============================================================

-- --------------------------------------------------------------
-- 启用 extensions
-- --------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS vector;               -- pgvector 向量搜索
CREATE EXTENSION IF NOT EXISTS pg_search;            -- ParadeDB BM25 全文搜索
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;   -- SQL 性能统计

-- --------------------------------------------------------------
-- 知识库文档表
-- --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS documents (
    id           SERIAL          PRIMARY KEY,
    file_path    TEXT            NOT NULL UNIQUE,   -- 原始 markdown 文件路径
    title        TEXT,
    content      TEXT            NOT NULL,           -- markdown 原文内容
    chunk_index  INT             NOT NULL DEFAULT 0, -- 分块索引（长文档切片）
    chunk_total  INT             NOT NULL DEFAULT 1, -- 该文档总块数
    embedding    vector(1536),                       -- 向量（维度与 embedding 模型一致）
    metadata     JSONB           DEFAULT '{}',       -- 扩展元数据（标签、分类等）
    created_at   TIMESTAMPTZ     DEFAULT now(),
    updated_at   TIMESTAMPTZ     DEFAULT now()
);

-- --------------------------------------------------------------
-- 索引
-- --------------------------------------------------------------

-- 向量近邻搜索索引（HNSW，cosine distance，适合语义搜索）
CREATE INDEX IF NOT EXISTS idx_documents_embedding
    ON documents
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- BM25 全文索引（关键词搜索 + 混合搜索用）
CREATE INDEX idx_documents_bm25
    ON documents
    USING bm25 (id, title, content)
    WITH (key_field = 'id');

-- 文件路径索引（按路径查询与去重）
CREATE INDEX IF NOT EXISTS idx_documents_file_path
    ON documents (file_path);

-- metadata JSONB 索引（按标签等元数据过滤）
CREATE INDEX IF NOT EXISTS idx_documents_metadata
    ON documents USING gin (metadata);

-- --------------------------------------------------------------
-- 自动更新 updated_at 触发器
-- --------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_documents_updated_at
    BEFORE UPDATE ON documents
    FOR EACH ROW EXECUTE FUNCTION fn_update_updated_at();
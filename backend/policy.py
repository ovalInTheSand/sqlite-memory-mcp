"""Simple policy layer for cross-agent access semantics.

Current rule set (minimal, extendable):
  - All agents can read base tables (memory, agents, projects, memory_graph, tasks)
  - Agent may write rows where agent_id = its own id (if ALLOW_WRITES)
  - Custom agent tables: write allowed only if table registered with matching agent_id
  - Future: plug in JSON policy definitions.
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import Set

BASE_READ_TABLES: Set[str] = {
    'memory','agents','projects','memory_graph','tasks','query_metrics','optimization_log','agent_tables'
}

@dataclass
class AgentContext:
    agent_id: int
    write_enabled: bool

class Policy:
    def can_read(self, agent: AgentContext, table: str) -> bool:
        return True  # open read model for now

    def can_write_row(self, agent: AgentContext, table: str, row_agent_id: int | None) -> bool:
        if not agent.write_enabled:
            return False
        if table == 'agent_tables':
            # Only allow registration for self
            return row_agent_id == agent.agent_id
        if table == 'memory':
            return row_agent_id in (agent.agent_id, None)
        return True  # default permissive, refine later

    def can_write_table(self, agent: AgentContext, table: str, owner_agent_id: int | None) -> bool:
        if not agent.write_enabled:
            return False
        if owner_agent_id is None:
            return True
        return owner_agent_id == agent.agent_id

    def can_create_relationship(self, agent: AgentContext, from_agent_id: int | None, to_agent_id: int | None) -> bool:
        """Disallow cross-agent relationships if both agent_ids are set and different.
        KISS: single rule centralization for future extension.
        """
        if not agent.write_enabled:
            return False
        if from_agent_id is None or to_agent_id is None:
            return True
        return from_agent_id == to_agent_id

load("logging.star", "log")
load("time.star", "time")
load("json.star", "json")
state = {}

def apply(metric):
  if state.get("init") == None:
    # Create node objects
    state["nodes"] = create_nodes_object(const_configured_partners);
    # Create HA group objects
    state["hagroups"] = create_hagroups_object(const_hagroups)
    
    state["quorumCount"] = len(state["nodes"].keys()) // 2 + 1;
    state["init"] = True;
    log.debug("Done initialising. State: " + str(state));

  if isClusterMessage(metric):
    
    log.debug("Handle clustermessage");
    nodeObject = state["nodes"].get(metric.tags.get(const_cluster_instance_name_tag));
    if nodeObject != None:
      log.debug("Partner found in config: " + metric.tags.get(const_cluster_instance_name_tag));
      
      nodeObject["lastSeen"] = time.now().unix_nano;
      nodeObject["votes"] = json.decode(metric.tags["votes"]);
      log.debug("Done processing votes: " + str(metric.tags["votes"]));
    
    # Drop received metric
    metric.fields.clear();

  elif isHeartbeatMessage(metric):
    # Validate timeout of nodes
    for nodeName, nodeObject in state["nodes"].items():
      previous_state = nodeObject["active"];
      nodeObject["active"] = not timeout(nodeObject["lastSeen"],const_cluster_active_timeout)
      if nodeObject["active"] != previous_state:
        nodeObject["lastChange"] = time.now().unix_nano;
      if nodeObject["active"] == False:
        nodeObject["online"] = False;
      elif timeout(nodeObject["lastChange"],const_cluster_online_threshold):
        nodeObject["online"] = True;
      log.debug("Node: " + nodeName + " is " + ("Active" if nodeObject["active"] else "Inactive") + " and " + ("Online" if nodeObject["online"] else "Offline"));
    # Vote
    votes = get_hagroup_votes(state);
    metric.tags["votes"] = json.encode(votes);
    log.debug("Voted: " + str(votes));
    
    # Count reveived votes
    count_hagroup_votes(state);

    log.debug("state: " + str(state));

  # Label other metrics with cluster info
  else:
    log.debug("Regular measurement");
    
    if isHAGroupMaster(state, metric.tags.get(const_hagroups_tag, "")):
      log.debug("Keep: " + str(metric));
    else:
      log.debug("Drop: " + str(metric));
      metric.fields.clear();

  return metric

def isClusterMessage(metric):
  return metric.tags.get(const_cluster_received_tag) != None;

def isHeartbeatMessage(metric):
  return metric.tags.get(const_cluster_heartbeat_tag) != None;

def isHAGroupMaster(state, hagroup_name):
  return state["hagroups"].get(hagroup_name, {}).get("isGroupMaster", False);

def create_hagroups_object(raw_config):
  hagroups_config = json.decode(raw_config);
  hagroups_object = {};
  for groupName, groupObject in hagroups_config.items():
    newHAgroup = {
      "nodes": [],
      "votes": 0,
      "voteCount": 0,
      "isGroupMaster": False,
    };
    # Example string in groupObject: "telegraf_1:10,telegraf_2:5"
    for item in groupObject.split(","):
      name, prio = item.split(":");
      newHAgroup["nodes"].append({"name": name, "prio": int(prio)});
    
    # Sort nodes highest priority first
    newHAgroup["nodes"] = sorted(newHAgroup["nodes"], key=lambda node: node["prio"], reverse=True);
    
    hagroups_object[groupName] = newHAgroup;
    
    log.debug("Created HA group in 'state.hagroups' : " + groupName);
  return hagroups_object;

def timeout(startTime, duration):
  return (time.now().unix_nano - startTime) > time.parse_duration(duration).nanoseconds;

def create_nodes_object(raw_config):
  node_object = {};
  for nodeName in raw_config.split(","):
    node_object[nodeName] = {
      "online": False,
      "active" : False,
      "lastSeen": 0,
      "lastChange": 0,
      "votes": {}
    };
    log.debug("Created node in 'state.nodes': " + nodeName);
  return node_object;

def get_hagroup_votes(state):
  """
  Returns a mapping of HA group names to the first online node name.

  Expects:
    state["nodes"]    -> dict keyed by node name, containing an 'online' boolean
    state["hagroups"] -> dict keyed by HA group name, each containing a 'nodes' list

  Returns:
    dict[str, str]
      {
        "hagroup1": "nodeA",
        "hagroup2": None,
        ...
      }
  """
  nodes = state.get("nodes", {});
  hagroups = state.get("hagroups", {});

  votes = {};

  for hagroup_name, hagroup in hagroups.items():
    votes[hagroup_name] = None;  # Default if no online node is found
    for hagroup_node in hagroup.get("nodes", []):
      name = hagroup_node.get("name");
      if nodes.get(name, {}).get("online") == True:
        votes[hagroup_name] = name;
        break;
  return votes

def count_hagroup_votes(state):
  nodes = state.get("nodes", {});
  hagroups = state.get("hagroups", {});
  quorumCount = state.get("quorumCount", 0);
  
  for hagroup_name, hagroup in hagroups.items():
    hagroup["votes"] = 0;
    hagroup["voteCount"] = 0;
    for node_name, node in nodes.items():
      if node["online"] == True:
        node_vote = node["votes"].get(hagroup_name);
        if node_vote == None:
          continue;
        if node_vote == const_local_instance_name:
          hagroup["votes"] += 1;
        hagroup["voteCount"] += 1;
    hagroup["isGroupMaster"] = hagroup["votes"] >= quorumCount;

    log.debug("This node is " + ("Master" if hagroup["isGroupMaster"] else "Slave") + " of hagroup: " + hagroup_name + " with " + str(hagroup["votes"]) + " votes from " + str(hagroup["voteCount"]) + " voting nodes");
